// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { RateLimiter } from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";
import { OFTAdapter } from "@layerzerolabs/oft-evm/contracts/OFTAdapter.sol";

/// @notice Locks a token on its home chain so it can be minted as an OFT elsewhere, capping how
///         fast value can leave.
/// @dev Local decimals are read from the token at construction, so one adapter serves any token.
///      Only safe for tokens with lossless transfers - a transfer fee would break the 1:1 accounting.
contract RateLimitedOFTAdapter is OFTAdapter, RateLimiter {
    /// @param _rateLimitConfigs Must cover every destination the adapter will send to. Destinations
    ///        without a configured limit can send nothing at all.
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate,
        RateLimitConfig[] memory _rateLimitConfigs
    ) OFTAdapter(_token, _lzEndpoint, _delegate) Ownable(_delegate) {
        _setRateLimits(_rateLimitConfigs);
    }

    function setRateLimits(RateLimitConfig[] calldata _rateLimitConfigs) external onlyOwner {
        _setRateLimits(_rateLimitConfigs);
    }

    /// @dev Caps how fast value can leave this chain, bounding the damage a compromised peer can do
    ///      before the owner unsets it. Charged on the requested amount, which is at or above the
    ///      amount that survives dust removal.
    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        _outflow(_dstEid, _amountLD);
        return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
    }
}
