// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { NativeOFTAdapterUpgradeable } from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/NativeOFTAdapterUpgradeable.sol";


contract NativeTokenOFTAdapter is NativeOFTAdapterUpgradeable {
    constructor(uint8 _localDecimals, address _lzEndpoint) NativeOFTAdapterUpgradeable(_localDecimals, _lzEndpoint) {
        _disableInitializers();
    }

    function initialize(address _delegate) external initializer {
        __Ownable_init(msg.sender);
        __NativeOFTAdapter_init(_delegate);
    }
}
