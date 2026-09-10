// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";

/// @notice Ethereum L1 representation of SOL and jitoSOL, both 9 decimals on Solana and on the
///         Derive representations these replace.
/// @dev Must stay pure: OFTUpgradeable reads `decimals()` while constructing, to fix
///      `decimalConversionRate`.
contract TokenOFT9 is OFTUpgradeable {
    bool public seeded;

    event Seeded(address indexed to, uint256 amount);

    error AlreadySeeded();

    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    /// @notice Mints, once, the supply that already exists on the chain this OFT replaces.
    function seed(address _to, uint256 _amount) external onlyOwner {
        if (seeded) revert AlreadySeeded();
        seeded = true;

        _mint(_to, _amount);
        emit Seeded(_to, _amount);
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
