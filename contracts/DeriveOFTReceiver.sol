// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTAdapterUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OftAdapterUpgradeable.sol";


interface MintBurnERC20 {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}


/// TODO: missing hooks on deposit
contract DeriveOFTReceiver is OFTAdapterUpgradeable {
    // Tracks total minted from each source chain (limits how much can be burnt back to that chain)
    mapping(uint32 eid => uint256) public lockedAmount;

    // Rate limiting for withdrawals
    uint256 public maxWithdrawLimit;
    uint256 public withdrawLimitRefresh; // Duration in seconds for limit refresh
    uint256 public currentWithdrawnAmount;
    uint256 public lastWithdrawRefreshTime;

    // Whitelist for addresses that can skip the rate limit
    mapping(address => bool) public withdrawWhitelist;

    // Guardian role - can bump limits and add to whitelist
    mapping(address => bool) public guardians;


    constructor(
        address token,
        address _lzEndpoint
    ) OFTAdapterUpgradeable(token, _lzEndpoint) {}

    function initialize(address _delegate) public initializer {
        __OFTAdapter_init(_delegate);
        __Ownable_init(msg.sender);
        lastWithdrawRefreshTime = block.timestamp;
    }

    /// @notice Set the withdraw rate limit parameters
    /// @param _maxWithdrawLimit Maximum amount that can be withdrawn per period
    /// @param _withdrawLimitRefresh Duration in seconds for limit refresh
    function setWithdrawLimit(uint256 _maxWithdrawLimit, uint256 _withdrawLimitRefresh) external onlyOwner {
        maxWithdrawLimit = _maxWithdrawLimit;
        withdrawLimitRefresh = _withdrawLimitRefresh;
        emit WithdrawLimitSet(_maxWithdrawLimit, _withdrawLimitRefresh);
    }

    /// @notice Add or remove a guardian
    /// @param account Address to update
    /// @param status True to add, false to remove
    function setGuardian(address account, bool status) external onlyOwner {
        guardians[account] = status;
        emit GuardianUpdated(account, status);
    }

    /// @notice Add or remove an address from the withdraw whitelist (Owner only)
    /// @param account Address to update
    /// @param status True to add, false to remove
    function setWhitelist(address account, bool status) external onlyGuardian {
        _setWhitelist(account, status);
    }

    /// @notice Bump the current withdrawn amount to max limit (Guardian can call)
    /// @dev This effectively resets the available limit to maximum
    function refreshWithdrawalLimit() external onlyGuardian {
        currentWithdrawnAmount = 0;
        lastWithdrawRefreshTime = block.timestamp;
        emit LimitBumpedToMax(msg.sender);
    }

    /// @notice Internal function to set whitelist status
    /// @param account Address to update
    /// @param status True to add, false to remove
    function _setWhitelist(address account, bool status) internal {
        withdrawWhitelist[account] = status;
        emit WhitelistUpdated(account, status);
    }

    /// @notice Internal function to check rate limit for withdrawals
    /// @param _from Address attempting to withdraw
    /// @param amountSentLD Amount to withdraw
    function _checkRateLimit(address _from, uint256 amountSentLD) internal {
        // Skip check if whitelisted
        if (withdrawWhitelist[_from]) return;

        // Skip check if no limit is set
        if (maxWithdrawLimit == 0 || withdrawLimitRefresh == 0) return;

        // Refresh the limit if the period has passed
        if (block.timestamp >= lastWithdrawRefreshTime + withdrawLimitRefresh) {
            currentWithdrawnAmount = 0;
            lastWithdrawRefreshTime = block.timestamp;
        }

        // Check if limit would be exceeded
        if (currentWithdrawnAmount + amountSentLD > maxWithdrawLimit) {
            revert WithdrawLimitExceeded(amountSentLD, maxWithdrawLimit - currentWithdrawnAmount);
        }

        // Update withdrawn amount
        currentWithdrawnAmount += amountSentLD;
    }

    /// @notice Get the current available withdraw limit
    function getAvailableWithdrawLimit() public view returns (uint256) {
        if (withdrawLimitRefresh == 0 || maxWithdrawLimit == 0) {
            return type(uint256).max; // No limit set
        }

        if (block.timestamp >= lastWithdrawRefreshTime + withdrawLimitRefresh) {
            return maxWithdrawLimit;
        }

        if (currentWithdrawnAmount >= maxWithdrawLimit) {
            return 0;
        }

        return maxWithdrawLimit - currentWithdrawnAmount;
    }

    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);

        // Check that we don't burn more than was minted from this chain
        if (amountSentLD > lockedAmount[_dstEid]) {
            revert InsufficientLockedAmount(_dstEid, amountSentLD, lockedAmount[_dstEid]);
        }

        // Check rate limit using internal function
        _checkRateLimit(_from, amountSentLD);

        // Decrease locked amount since we're burning tokens to send back to that chain
        lockedAmount[_dstEid] -= amountSentLD;

        MintBurnERC20(address(innerToken)).burn(_from, amountSentLD);
    }

    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) internal virtual override returns (uint256 amountReceivedLD) {
        // Track the minted amount from this source chain
        lockedAmount[_srcEid] += _amountLD;

        // @dev Unlock the tokens and transfer to the recipient.
        MintBurnERC20(address(innerToken)).mint(_to, _amountLD);
        // @dev In the case of NON-default OFTAdapter, the amountLD MIGHT not be == amountReceivedLD.
        return _amountLD;
    }

    ///////////////
    // Modifiers //
    ///////////////

    /// @notice Modifier to restrict access to guardians only
    modifier onlyGuardian() {
        if (!guardians[msg.sender]) revert OnlyGuardian();
        _;
    }


    ///////////////////////
    // Errors and Events //
    ///////////////////////
    error WithdrawLimitExceeded(uint256 requested, uint256 available);
    error InsufficientLockedAmount(uint32 dstEid, uint256 requested, uint256 available);
    error OnlyGuardian();

    event WithdrawLimitSet(uint256 maxLimit, uint256 refreshDuration);
    event WhitelistUpdated(address account, bool status);
    event GuardianUpdated(address account, bool status);
    event LimitBumpedToMax(address guardian);
}
