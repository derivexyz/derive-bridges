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
 * @title OFTSource
 * @dev Source chain OFT contract for many-to-one bridge architecture
 * This contract burns tokens on source chains and sends them to the destination chain
 * Works on EVM and TRON chains (shared Solidity codebase)
 */
contract OFTSource is ERC20, ERC20Burnable, Ownable, ReentrancyGuard, IOFTCore, ILayerZeroReceiver {
    // LayerZero endpoint for cross-chain messaging
    ILayerZeroEndpoint public immutable lzEndpoint;
    
    // Destination chain ID (canonical chain)
    uint16 public immutable destinationChainId;
    
    // Destination contract address
    bytes public destinationAddress;
    
    // Nonce for tracking cross-chain messages
    uint64 private nonce;
    
    // Minimum gas for destination chain execution
    uint256 public constant MIN_GAS_DESTINATION = 200000;
    
    // Mapping to track trusted remote contracts
    mapping(uint16 => bytes) public trustedRemotes;
    
    // Pause mechanism for emergency
    bool public paused;
    
    /**
     * @dev Events
     */
    event SetTrustedRemote(uint16 indexed remoteChainId, bytes remoteAddress);
    event SetDestinationAddress(bytes destinationAddress);
    event Paused(bool paused);
    
    /**
     * @dev Errors
     */
    error ContractPaused();
    error InvalidDestinationChain();
    error InvalidRemoteAddress();
    error InsufficientFee();
    error UnauthorizedCaller();
    error InvalidNonce();
    
    /**
     * @dev Constructor
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _lzEndpoint LayerZero endpoint address
     * @param _destinationChainId Destination chain ID
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        uint16 _destinationChainId
    ) ERC20(_name, _symbol) Ownable(msg.sender) {
        require(_lzEndpoint != address(0), "Invalid endpoint");
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
        destinationChainId = _destinationChainId;
    }
    
    /**
     * @dev Modifier to check if contract is not paused
     */
    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }
    
    /**
     * @dev Set destination contract address
     * @param _destinationAddress Destination contract address
     */
    function setDestinationAddress(bytes calldata _destinationAddress) external onlyOwner {
        require(_destinationAddress.length > 0, "Invalid address");
        destinationAddress = _destinationAddress;
        trustedRemotes[destinationChainId] = _destinationAddress;
        emit SetDestinationAddress(_destinationAddress);
        emit SetTrustedRemote(destinationChainId, _destinationAddress);
    }
    
    /**
     * @dev Set trusted remote contract for a chain
     * @param _remoteChainId Remote chain ID
     * @param _remoteAddress Remote contract address
     */
    function setTrustedRemote(uint16 _remoteChainId, bytes calldata _remoteAddress) external onlyOwner {
        require(_remoteAddress.length > 0, "Invalid address");
        trustedRemotes[_remoteChainId] = _remoteAddress;
        emit SetTrustedRemote(_remoteChainId, _remoteAddress);
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
     * @dev Send tokens to destination chain
     * @param dstChainId Destination chain ID (must be canonical chain)
     * @param toAddress Recipient address on destination chain
     * @param amount Amount of tokens to send
     */
    function sendToChain(
        uint16 dstChainId,
        bytes calldata toAddress,
        uint256 amount
    ) external payable override nonReentrant whenNotPaused returns (uint64) {
        // Validate destination chain
        if (dstChainId != destinationChainId) revert InvalidDestinationChain();
        if (destinationAddress.length == 0) revert InvalidRemoteAddress();
        
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
            destinationAddress,
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
            revert InvalidRemoteAddress();
        }
        
        // Decode payload and mint tokens (for destination -> source refunds)
        (address toAddress, uint256 amount) = abi.decode(payload, (address, uint256));
        _mint(toAddress, amount);
        
        emit ReceiveFromChain(srcChainId, srcAddress, toAddress, amount, _nonce);
    }
    
    /**
     * @dev Mint tokens (only owner can mint on source chains for initial supply)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
