// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTToken } from "./OFTToken.sol";

/// @notice OFTToken for a pathway that replaces an existing representation, whose frozen supply is
///         minted here once so holders keep what they already hold.
abstract contract OFTTokenSeeded is OFTToken {
    bool public seeded;

    event Seeded(address indexed to, uint256 amount);

    error AlreadySeeded();

    /// @notice Mints, once, the supply that already exists on the chain this OFT replaces.
    function seed(address _to, uint256 _amount) external onlyOwner {
        if (seeded) revert AlreadySeeded();
        seeded = true;

        _mint(_to, _amount);
        emit Seeded(_to, _amount);
    }
}

/// @notice SOL and jitoSOL, both 9 decimals on Solana and on the Derive representations these replace.
contract OFTToken9Seeded is OFTTokenSeeded {
    constructor(address _lzEndpoint) OFTToken(_lzEndpoint) {}

    function decimals() public pure override returns (uint8) {
        return 9;
    }
}
