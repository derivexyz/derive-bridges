// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { IOFT, SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { NativeTokenOFTAdapter } from "../../contracts/NativeTokenOFTAdapter.sol";
import { TokenOFT18 } from "../../contracts/TokenOFT18.sol";
import { TokenOFT6 } from "../../contracts/TokenOFT6.sol";
import { TokenOFT9 } from "../../contracts/TokenOFT9.sol";
import { TokenOFTAdapter } from "../../contracts/TokenOFTAdapter.sol";
import { StandInToken } from "../../contracts/testnet/StandInToken.sol";

/// @notice Stands up one pathway of the real mesh: a hub OFT that mints against an escrow held by an
///         adapter on the token's home chain.
/// @dev Deployed behind proxies as they will be in production - the implementations disable their
///      initializers, so they cannot be driven directly.
abstract contract BridgeFixture is TestHelperOz5 {
    using OptionsBuilder for bytes;

    uint32 internal constant HUB_EID = 1;
    uint32 internal constant HOME_EID = 2;

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);
    }

    /// @param _decimals Picks the hub variant, and the home token is given the same, which is the
    ///        property these tests exist to hold.
    function _deployPair(
        uint8 _decimals
    ) internal returns (IOFT hub, TokenOFTAdapter adapter, StandInToken token) {
        token = new StandInToken("Home Token", "HOME", _decimals);

        address hubImpl;
        if (_decimals == 18) {
            hubImpl = address(new TokenOFT18(address(endpoints[HUB_EID])));
        } else if (_decimals == 9) {
            hubImpl = address(new TokenOFT9(address(endpoints[HUB_EID])));
        } else {
            hubImpl = address(new TokenOFT6(address(endpoints[HUB_EID])));
        }

        // The three variants share an initialize signature, so one selector serves all of them.
        hub = IOFT(
            address(
                new ERC1967Proxy(
                    hubImpl,
                    abi.encodeCall(TokenOFT18.initialize, ("Hub Token", "HUB", address(this)))
                )
            )
        );

        address adapterImpl = address(new TokenOFTAdapter(address(token), address(endpoints[HOME_EID])));
        adapter = TokenOFTAdapter(
            address(
                new ERC1967Proxy(adapterImpl, abi.encodeCall(TokenOFTAdapter.initialize, (address(this))))
            )
        );

        _wire(address(hub), address(adapter));
    }

    function _deployNativePair() internal returns (IOFT hub, NativeTokenOFTAdapter adapter) {
        address hubImpl = address(new TokenOFT18(address(endpoints[HUB_EID])));
        hub = IOFT(
            address(
                new ERC1967Proxy(
                    hubImpl,
                    abi.encodeCall(TokenOFT18.initialize, ("Hub Native", "HUBN", address(this)))
                )
            )
        );

        address adapterImpl = address(new NativeTokenOFTAdapter(18, address(endpoints[HOME_EID])));
        adapter = NativeTokenOFTAdapter(
            address(
                new ERC1967Proxy(
                    adapterImpl,
                    abi.encodeCall(NativeTokenOFTAdapter.initialize, (address(this)))
                )
            )
        );

        _wire(address(hub), address(adapter));
    }

    function _wire(address _hub, address _adapter) private {
        address[] memory oapps = new address[](2);
        oapps[0] = _hub;
        oapps[1] = _adapter;
        this.wireOApps(oapps);
    }

    function _sendParam(
        uint32 _dstEid,
        address _to,
        uint256 _amount,
        uint128 _lzReceiveGas
    ) internal pure returns (SendParam memory) {
        return
            SendParam({
                dstEid: _dstEid,
                to: bytes32(uint256(uint160(_to))),
                amountLD: _amount,
                minAmountLD: 0,
                extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(_lzReceiveGas, 0),
                composeMsg: "",
                oftCmd: ""
            });
    }
}
