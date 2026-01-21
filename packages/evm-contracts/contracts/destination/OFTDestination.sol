// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IOFTCore.sol";
import "../interfaces/ILayerZeroEndpoint.sol";
import "../interfaces/ILayerZeroReceiver.sol";

/**
 * @title OFTDestination
 * @dev Destination chain (canonical) OFT contract for many-to-one bridge architecture
 * This contract mints tokens when receiving from source chains and burns when sending back
 * Deployed on the canonical destination chain
 */
contract OFTDestination is ERC20, ERC20Burnable, Ownable, ReentrancyGuard, IOFTCore, ILayerZeroReceiver {
    // LayerZero endpoint for cross-chain messaging
    ILayerZeroEndpoint public immutable lzEndpoint;
    
    // Nonce for tracking cross-chain messages
    uint64 private nonce;
    
    // Minimum gas for source chain execution
    uint256 public constant MIN_GAS_SOURCE = 200000;
    
    // Mapping to track trusted remote contracts (source chains)
    mapping(uint16 => bytes) public trustedRemotes;
    
    // Pause mechanism for emergency
    bool public paused;
    
    // Total supply cap (optional)
    uint256 public supplyCap;
    
    /**
     * @dev Events
     */
    event SetTrustedRemote(uint16 indexed remoteChainId, bytes remoteAddress);
    event Paused(bool paused);
    event SupplyCapUpdated(uint256 newCap);
    
    /**
     * @dev Errors
     */
    error ContractPaused();
    error InvalidRemoteAddress();
    error InsufficientFee();
    error UnauthorizedCaller();
    error InvalidNonce();
    error SupplyCapExceeded();
    error UntrustedRemote();
    
    /**
     * @dev Constructor
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _lzEndpoint LayerZero endpoint address
     * @param _supplyCap Maximum supply cap (0 for unlimited)
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        uint256 _supplyCap
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        require(_lzEndpoint != address(0), "Invalid endpoint");
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
        supplyCap = _supplyCap;
    }
    
    /**
     * @dev Modifier to check if contract is not paused
     */
    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }
    
    /**
     * @dev Set trusted remote contract for a source chain
     * @param _remoteChainId Remote chain ID
     * @param _remoteAddress Remote contract address
     */
    function setTrustedRemote(uint16 _remoteChainId, bytes calldata _remoteAddress) external onlyOwner {
        require(_remoteAddress.length > 0, "Invalid address");
        trustedRemotes[_remoteChainId] = _remoteAddress;
        emit SetTrustedRemote(_remoteChainId, _remoteAddress);
    }
    
    /**
     * @dev Remove trusted remote contract
     * @param _remoteChainId Remote chain ID to remove
     */
    function removeTrustedRemote(uint16 _remoteChainId) external onlyOwner {
        delete trustedRemotes[_remoteChainId];
        emit SetTrustedRemote(_remoteChainId, bytes(""));
    }
    
    /**
     * @dev Pause/unpause the contract
     * @param _paused Pause status
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }
    
    /**
     * @dev Update supply cap
     * @param _newCap New supply cap (0 for unlimited)
     */
    function setSupplyCap(uint256 _newCap) external onlyOwner {
        supplyCap = _newCap;
        emit SupplyCapUpdated(_newCap);
    }
    
    /**
     * @dev Send tokens back to source chain
     * @param dstChainId Destination chain ID (source chain)
     * @param toAddress Recipient address on destination chain
     * @param amount Amount of tokens to send
     */
    function sendToChain(
        uint16 dstChainId,
        bytes calldata toAddress,
        uint256 amount
    ) external payable override nonReentrant whenNotPaused returns (uint64) {
        // Validate destination chain has a trusted remote
        if (trustedRemotes[dstChainId].length == 0) revert InvalidRemoteAddress();
        
        // Burn tokens from sender
        _burn(msg.sender, amount);
        
        // Prepare payload
        bytes memory payload = abi.encode(toAddress, amount);
        
        // Estimate and validate fee
        (uint256 nativeFee, ) = lzEndpoint.estimateFees(
            dstChainId,
            address(this),
            payload,
            false,
            bytes("")
        );
        
        if (msg.value < nativeFee) revert InsufficientFee();
        
        // Increment nonce
        uint64 currentNonce = ++nonce;
        
        // Send cross-chain message
        lzEndpoint.send{value: msg.value}(
            dstChainId,
            trustedRemotes[dstChainId],
            payload,
            payable(msg.sender),
            address(0),
            bytes("")
        );
        
        emit SendToChain(dstChainId, msg.sender, toAddress, amount, currentNonce);
        
        return currentNonce;
    }
    
    /**
     * @dev Estimate fee for sending tokens
     * @param dstChainId Destination chain ID
     * @param amount Amount of tokens to send
     */
    function estimateSendFee(
        uint16 dstChainId,
        uint256 amount
    ) external view override returns (uint256 nativeFee) {
        bytes memory payload = abi.encode(bytes(""), amount);
        (nativeFee, ) = lzEndpoint.estimateFees(
            dstChainId,
            address(this),
            payload,
            false,
            bytes("")
        );
    }
    
    /**
     * @dev Receive cross-chain message from LayerZero
     * @param srcChainId Source chain ID
     * @param srcAddress Source contract address
     * @param _nonce Message nonce
     * @param payload Message payload
     */
    function lzReceive(
        uint16 srcChainId,
        bytes calldata srcAddress,
        uint64 _nonce,
        bytes calldata payload
    ) external override {
        // Only LayerZero endpoint can call this
        if (msg.sender != address(lzEndpoint)) revert UnauthorizedCaller();
        
        // Verify trusted remote
        if (keccak256(srcAddress) != keccak256(trustedRemotes[srcChainId])) {
            revert UntrustedRemote();
        }
        
        // Decode payload
        (bytes memory toAddressBytes, uint256 amount) = abi.decode(payload, (bytes, uint256));
        address toAddress = _bytesToAddress(toAddressBytes);
        
        // Check supply cap
        if (supplyCap > 0 && totalSupply() + amount > supplyCap) {
            revert SupplyCapExceeded();
        }
        
        // Mint tokens to recipient
        _mint(toAddress, amount);
        
        emit ReceiveFromChain(srcChainId, srcAddress, toAddress, amount, _nonce);
    }
    
    /**
     * @dev Convert bytes to address
     * @param _bytes Bytes to convert
     */
    function _bytesToAddress(bytes memory _bytes) internal pure returns (address) {
        require(_bytes.length >= 20, "Invalid address length");
        address tempAddress;
        assembly {
            tempAddress := mload(add(_bytes, 20))
        }
        return tempAddress;
    }
    
    /**
     * @dev Check if a remote is trusted
     * @param chainId Chain ID to check
     */
    function isTrustedRemote(uint16 chainId) external view returns (bool) {
        return trustedRemotes[chainId].length > 0;
    }
}
