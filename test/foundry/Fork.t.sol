// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { NativeTokenOFTAdapter } from "../../contracts/NativeTokenOFTAdapter.sol";
import { TokenOFT18 } from "../../contracts/TokenOFT18.sol";
import { TokenOFT6 } from "../../contracts/TokenOFT6.sol";
import { TokenOFT9 } from "../../contracts/TokenOFT9.sol";
import { TokenOFTAdapter } from "../../contracts/TokenOFTAdapter.sol";

/// @notice Deploys the implementations against the real endpoints and real tokens on forked chains.
///         Unit tests cannot catch a wrong endpoint address or a token whose decimals are not what the
///         config assumes, because both are supplied rather than derived.
/// @dev Skips rather than fails when a fork is unreachable, so the suite still runs offline.
contract ForkTest is Test {
    // EndpointV2, from @layerzerolabs/lz-evm-sdk-v2 deployments.
    address internal constant ENDPOINT_ETHEREUM = 0x1a44076050125825900e736c501f859c50fE728c;
    address internal constant ENDPOINT_FLARE = 0x1a44076050125825900e736c501f859c50fE728c;
    address internal constant ENDPOINT_HYPEREVM = 0x3A73033C0b1407574C76BdBAc67f126f6b4a9AA9;

    // What hardhat.config.ts hands the fXRP adapter.
    address internal constant FXRP_FLARE = 0xAd552A648C74D49E10027AB8a618A3ad4901c5bE;

    uint256 internal constant SHARED_DECIMALS = 6;

    function _forked(string memory _chainAlias) private returns (bool) {
        try vm.rpcUrl(_chainAlias) returns (string memory url) {
            try vm.createSelectFork(url) returns (uint256) {
                return true;
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }

    function _assertIsEndpoint(address _endpoint) private view {
        assertGt(_endpoint.code.length, 0, "no contract at the configured endpoint");
    }

    /// The adapter reads decimals off the token in its constructor, so a wrong assumption here silently
    /// misdenominates the whole pathway. This is the check that pins fXRP to TokenOFT6.
    function test_flare_fxrpIsSixDecimals() public {
        if (!_forked("flare")) return vm.skip(true);

        assertEq(IERC20Metadata(FXRP_FLARE).decimals(), 6, "fXRP is not 6 decimals");
        assertEq(IERC20Metadata(FXRP_FLARE).symbol(), "FXRP", "not the fXRP token");
    }

    function test_flare_adapterMatchesToken() public {
        if (!_forked("flare")) return vm.skip(true);
        _assertIsEndpoint(ENDPOINT_FLARE);

        TokenOFTAdapter adapter = new TokenOFTAdapter(FXRP_FLARE, ENDPOINT_FLARE);

        assertEq(adapter.token(), FXRP_FLARE, "adapter escrows the wrong token");
        assertEq(
            adapter.decimalConversionRate(),
            10 ** (uint256(IERC20Metadata(FXRP_FLARE).decimals()) - SHARED_DECIMALS),
            "conversion rate does not follow the token"
        );
    }

    function test_hyperevm_nativeAdapterAgainstRealEndpoint() public {
        if (!_forked("hyperevm")) return vm.skip(true);
        _assertIsEndpoint(ENDPOINT_HYPEREVM);

        NativeTokenOFTAdapter adapter = new NativeTokenOFTAdapter(18, ENDPOINT_HYPEREVM);

        assertEq(adapter.token(), address(0), "native adapter should report no token");
        assertEq(adapter.decimalConversionRate(), 10 ** (18 - SHARED_DECIMALS), "wrong rate for 18 decimals");
    }

    /// kHYPE's address is still unset in hardhat.config.ts. When it is filled in, run this with
    /// KHYPE_HYPEREVM_MAINNET set and it checks the same property the fXRP test does.
    function test_hyperevm_khypeMatchesAdapter() public {
        address khype = vm.envOr("KHYPE_HYPEREVM_MAINNET", address(0));
        if (khype == address(0)) return vm.skip(true);
        if (!_forked("hyperevm")) return vm.skip(true);

        TokenOFTAdapter adapter = new TokenOFTAdapter(khype, ENDPOINT_HYPEREVM);

        assertEq(adapter.token(), khype, "adapter escrows the wrong token");
        assertEq(
            adapter.decimalConversionRate(),
            10 ** (uint256(IERC20Metadata(khype).decimals()) - SHARED_DECIMALS),
            "conversion rate does not follow the token"
        );
    }

    /// Each hub variant against the real Ethereum endpoint, since decimals are burned into the
    /// implementation's bytecode and cannot be corrected by an upgrade argument.
    function test_ethereum_hubVariantsCarryTheirDecimals() public {
        if (!_forked("ethereum")) return vm.skip(true);
        _assertIsEndpoint(ENDPOINT_ETHEREUM);

        TokenOFT18 hub18 = new TokenOFT18(ENDPOINT_ETHEREUM);
        TokenOFT9 hub9 = new TokenOFT9(ENDPOINT_ETHEREUM);
        TokenOFT6 hub6 = new TokenOFT6(ENDPOINT_ETHEREUM);

        assertEq(hub18.decimals(), 18);
        assertEq(hub9.decimals(), 9);
        assertEq(hub6.decimals(), 6);

        assertEq(hub18.decimalConversionRate(), 10 ** (18 - SHARED_DECIMALS));
        assertEq(hub9.decimalConversionRate(), 10 ** (9 - SHARED_DECIMALS));
        assertEq(hub6.decimalConversionRate(), 1);
    }
}
