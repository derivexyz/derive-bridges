// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";

/// @notice Ethereum L1 representation of a token whose home is another chain. Decimals must match
///         the home chain's token, and each value is its own contract below.
abstract contract OFTToken is OFTUpgradeable {
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
}

contract OFTToken6 is OFTToken {
    constructor(address _lzEndpoint) OFTToken(_lzEndpoint) {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract OFTToken18 is OFTToken {
    constructor(address _lzEndpoint) OFTToken(_lzEndpoint) {}

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}

contract OFTToken8 is OFTToken {
    constructor(address _lzEndpoint) OFTToken(_lzEndpoint) {}

    function decimals() public pure override returns (uint8) {
        return 8;
    }
}
