// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OFTAdapterUpgradeable} from "@lz-devtools-oft/oft/OFTAdapterUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title OFTSourceAdapter
 * @dev Source chain OFT adapter for many-to-one bridge architecture
 * @dev Inherits from LayerZero's OFTAdapterUpgradeable
 * @dev This contract:
 * - Takes ERC20 tokens via approval (user approves -> calls send)
 * - Locks the tokens in the adapter
 * - Sends cross-chain message to mint on destination
 * - Works on EVM and TRON chains (shared Solidity codebase)
 */
contract OFTSourceAdapter is OFTAdapterUpgradeable, OwnableUpgradeable {
    /// @notice Destination chain endpoint ID
    uint32 public immutable destinationEid;

    /// @notice Emitted when the contract is paused/unpaused
    event Paused(bool paused);

    /// @notice Contract pause state
    bool public paused;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address _token,
        address _lzEndpoint,
        uint32 _destinationEid
    ) OFTAdapterUpgradeable(_token, _lzEndpoint) {
        destinationEid = _destinationEid;
        _disableInitializers();
    }

    /**
     * @notice Initializes the OFTSourceAdapter
     * @param _owner The owner address
     */
    function initialize(address _owner) external initializer {
        __OFTAdapter_init(_owner);
        __Ownable_init(_owner);
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
     * @dev Override to add pause check
     */
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        require(!paused, "OFTSourceAdapter: paused");
        return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
    }

    /**
     * @dev Override to add pause check
     */
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override returns (uint256 amountReceivedLD) {
        require(!paused, "OFTSourceAdapter: paused");
        return super._credit(_to, _amountLD, _srcEid);
    }
}
