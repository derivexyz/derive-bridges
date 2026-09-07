// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";

/// @notice Ethereum L1 representation of SOL and jitoSOL, both 9 decimals on Solana and on the
///         Derive representations these replace.
/// @dev Must stay pure: OFTUpgradeable reads `decimals()` while constructing, to fix
///      `decimalConversionRate`.
contract TokenOFT9 is OFTUpgradeable {
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    function initialize(
        string memory _tokenName,
        string memory _tokenSymbol,
        address _delegate
    ) external initializer {
        __Ownable_init(msg.sender);
        __OFT_init(_tokenName, _tokenSymbol, _delegate);
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }
}
