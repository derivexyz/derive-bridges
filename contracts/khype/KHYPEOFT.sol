// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { RateLimiter } from "@layerzerolabs/oapp-evm/contracts/oapp/utils/RateLimiter.sol";
import { OFT } from "@layerzerolabs/oft-evm/contracts/OFT.sol";

/// @notice Ethereum mainnet representation of HyperEVM's kHYPE, minted against kHYPE locked in the
///         RateLimitedOFTAdapter on HyperEVM.
contract KHYPEOFT is OFT, RateLimiter {
    /// @param _rateLimitConfigs Must cover every destination this OFT will send to. Destinations
    ///        without a configured limit can send nothing at all.
    constructor(
        address _lzEndpoint,
        address _delegate,
        RateLimitConfig[] memory _rateLimitConfigs
    ) OFT("kHYPE", "kHYPE", _lzEndpoint, _delegate) Ownable(_delegate) {
        _setRateLimits(_rateLimitConfigs);
    }

    /// @dev Matches kHYPE on HyperEVM. Above sharedDecimals(), so amounts are truncated to 6 decimal
    ///      places when bridging. Must stay a constant: OFT reads it while constructing.
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function setRateLimits(RateLimitConfig[] calldata _rateLimitConfigs) external onlyOwner {
        _setRateLimits(_rateLimitConfigs);
    }

    /// @dev Caps how fast the HyperEVM escrow can be drained if this side is ever able to mint more
    ///      than is locked.
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
