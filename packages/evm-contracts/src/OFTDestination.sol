// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OFTUpgradeable} from "@lz-devtools-oft/oft/OFTUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title OFTDestination
 * @dev Destination chain (canonical) OFT contract for many-to-one bridge architecture
 * @dev Inherits from LayerZero's OFTUpgradeable
 * @dev This contract:
 * - Mints tokens when receiving from source chains
 * - Burns tokens when sending back to source chains
 * - Tracks liquidity per source chain to prevent overdrafts
 * - Deployed on the canonical destination chain
 */
contract OFTDestination is OFTUpgradeable, OwnableUpgradeable {
    /// @notice Tracks the total amount minted for each source chain (by endpoint ID)
    /// @dev This prevents withdrawing more than what was bridged from a specific chain
    mapping(uint32 => uint256) public chainLiquidity;

    /// @notice Maximum supply cap (0 = unlimited)
    uint256 public supplyCap;

    /// @notice Contract pause state
    bool public paused;

    /// @notice Emitted when liquidity is updated for a chain
    event ChainLiquidityUpdated(uint32 indexed srcEid, uint256 newLiquidity);

    /// @notice Emitted when supply cap is updated
    event SupplyCapUpdated(uint256 newCap);

    /// @notice Emitted when the contract is paused/unpaused
    event Paused(bool paused);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    /**
     * @notice Initializes the OFTDestination
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _owner The owner address
     * @param _supplyCap Maximum supply (0 for unlimited)
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        address _owner,
        uint256 _supplyCap
    ) external initializer {
        __OFT_init(_name, _symbol, _owner);
        __Ownable_init(_owner);
        supplyCap = _supplyCap;
    }

    /**
     * @notice Set the supply cap
     * @param _newCap New supply cap (0 for unlimited)
     */
    function setSupplyCap(uint256 _newCap) external onlyOwner {
        supplyCap = _newCap;
        emit SupplyCapUpdated(_newCap);
    }

    /**
     * @notice Pause/unpause the contract
     * @param _paused New pause state
     */
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit Paused(_paused);
    }

    /**
     * @notice Check if a chain has sufficient liquidity for withdrawal
     * @param _srcEid Source chain endpoint ID
     * @param _amount Amount to check
     * @return bool True if sufficient liquidity exists
     */
    function hasSufficientLiquidity(uint32 _srcEid, uint256 _amount) public view returns (bool) {
        return chainLiquidity[_srcEid] >= _amount;
    }

    /**
     * @dev Override _debit to track liquidity when sending back to source chains
     * @dev Burns tokens and decreases the source chain's liquidity
     */
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        require(!paused, "OFTDestination: paused");

        // Check if destination chain has enough liquidity
        require(
            hasSufficientLiquidity(_dstEid, _amountLD),
            "OFTDestination: insufficient liquidity on destination chain"
        );

        // Decrease liquidity for the destination chain
        chainLiquidity[_dstEid] -= _amountLD;
        emit ChainLiquidityUpdated(_dstEid, chainLiquidity[_dstEid]);

        // Burn tokens (default OFTUpgradeable behavior)
        return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
    }

    /**
     * @dev Override _credit to track liquidity when receiving from source chains
     * @dev Mints tokens and increases the source chain's liquidity
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override returns (uint256 amountReceivedLD) {
        require(!paused, "OFTDestination: paused");

        // Check supply cap
        if (supplyCap > 0) {
            require(totalSupply() + _amountLD <= supplyCap, "OFTDestination: supply cap exceeded");
        }

        // Increase liquidity for the source chain
        chainLiquidity[_srcEid] += _amountLD;
        emit ChainLiquidityUpdated(_srcEid, chainLiquidity[_srcEid]);

        // Mint tokens (default OFTUpgradeable behavior)
        return super._credit(_to, _amountLD, _srcEid);
    }

    /**
     * @notice Get the liquidity available for a specific chain
     * @param _eid Endpoint ID of the chain
     * @return uint256 Available liquidity
     */
    function getChainLiquidity(uint32 _eid) external view returns (uint256) {
        return chainLiquidity[_eid];
    }
}
