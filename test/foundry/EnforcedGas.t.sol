// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IOFT, SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import { BridgeFixture } from "./BridgeFixture.sol";
import { NativeTokenOFTAdapter } from "../../contracts/NativeTokenOFTAdapter.sol";
import { TokenOFTAdapter } from "../../contracts/TokenOFTAdapter.sol";
import { TokenMock } from "../mocks/TokenMock.sol";

/// @notice Recipient whose bookkeeping on receipt costs more than a bare transfer, as a Safe or vault's
///         would. Five cold storage writes put it comfortably past 80,000.
contract BookkeepingRecipient {
    uint256[] private received;

    receive() external payable {
        for (uint256 i = 0; i < 5; i++) {
            received.push(block.number + i);
        }
    }
}

/// @notice EVM_ENFORCED_OPTIONS in tasks/common/constants.ts sets a single lzReceive floor of 80,000 gas
///         for every pathway. The harness delivers with exactly the option's gas, so these tests measure
///         the real thing: too low a floor strands messages until someone re-executes them by hand.
contract EnforcedGasTest is BridgeFixture {
    /// EVM_ENFORCED_OPTIONS: the ERC20 pathways.
    uint128 private constant ENFORCED_LZRECEIVE_GAS = 80_000;

    /// NATIVE_EVM_ENFORCED_OPTIONS: HyperEVM-inbound on the native HYPE pathway.
    uint128 private constant NATIVE_ENFORCED_LZRECEIVE_GAS = 200_000;

    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");

    function setUp() public override {
        super.setUp();
        vm.deal(alice, 1_000 ether);
    }

    function test_hubMint_fitsEnforcedGas() public {
        (IOFT hub, TokenOFTAdapter adapter, TokenMock token) = _deployPair(18);

        uint256 amount = 1e18;
        token.mint(alice, amount);

        SendParam memory sendParam = _sendParam(HUB_EID, bob, amount, ENFORCED_LZRECEIVE_GAS);
        MessagingFee memory fee = IOFT(address(adapter)).quoteSend(sendParam, false);

        vm.startPrank(alice);
        token.approve(address(adapter), amount);
        IOFT(address(adapter)).send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        verifyPackets(HUB_EID, bytes32(uint256(uint160(address(hub)))));

        assertEq(IERC20(address(hub)).balanceOf(bob), amount, "mint did not fit in the enforced gas");
    }

    function test_escrowRelease_fitsEnforcedGas() public {
        (IOFT hub, TokenOFTAdapter adapter, TokenMock token) = _deployPair(18);

        uint256 amount = 1e18;
        token.mint(alice, amount);

        SendParam memory outbound = _sendParam(HUB_EID, alice, amount, 200_000);
        MessagingFee memory outboundFee = IOFT(address(adapter)).quoteSend(outbound, false);
        vm.startPrank(alice);
        token.approve(address(adapter), amount);
        IOFT(address(adapter)).send{ value: outboundFee.nativeFee }(outbound, outboundFee, alice);
        vm.stopPrank();
        verifyPackets(HUB_EID, bytes32(uint256(uint160(address(hub)))));

        // Back the other way, this time on the enforced floor.
        SendParam memory inbound = _sendParam(HOME_EID, bob, amount, ENFORCED_LZRECEIVE_GAS);
        MessagingFee memory inboundFee = hub.quoteSend(inbound, false);
        vm.prank(alice);
        hub.send{ value: inboundFee.nativeFee }(inbound, inboundFee, alice);

        verifyPackets(HOME_EID, bytes32(uint256(uint160(address(adapter)))));

        assertEq(token.balanceOf(bob), amount, "release did not fit in the enforced gas");
    }

    function test_nativeCredit_toEoa_fitsEnforcedGas() public {
        (IOFT hub, NativeTokenOFTAdapter adapter) = _deployNativePair();

        uint256 amount = 1 ether;
        SendParam memory outbound = _sendParam(HUB_EID, alice, amount, 200_000);
        MessagingFee memory outboundFee = IOFT(address(adapter)).quoteSend(outbound, false);

        // NativeOFTAdapter takes the amount alongside the fee as msg.value.
        vm.prank(alice);
        IOFT(address(adapter)).send{ value: outboundFee.nativeFee + amount }(outbound, outboundFee, alice);
        verifyPackets(HUB_EID, bytes32(uint256(uint160(address(hub)))));

        SendParam memory inbound = _sendParam(HOME_EID, bob, amount, ENFORCED_LZRECEIVE_GAS);
        MessagingFee memory inboundFee = hub.quoteSend(inbound, false);
        vm.prank(alice);
        hub.send{ value: inboundFee.nativeFee }(inbound, inboundFee, alice);

        verifyPackets(HOME_EID, bytes32(uint256(uint160(address(adapter)))));

        assertEq(bob.balance, amount, "native credit did not fit in the enforced gas");
    }

    /// @dev Runs one native credit to `_recipient` at `_gas`, returning whether it landed.
    function _nativeCreditLands(address _recipient, uint128 _gas) private returns (bool) {
        (IOFT hub, NativeTokenOFTAdapter adapter) = _deployNativePair();

        uint256 amount = 1 ether;
        SendParam memory outbound = _sendParam(HUB_EID, alice, amount, 500_000);
        MessagingFee memory outboundFee = IOFT(address(adapter)).quoteSend(outbound, false);
        vm.prank(alice);
        IOFT(address(adapter)).send{ value: outboundFee.nativeFee + amount }(outbound, outboundFee, alice);
        verifyPackets(HUB_EID, bytes32(uint256(uint160(address(hub)))));

        SendParam memory inbound = _sendParam(HOME_EID, _recipient, amount, _gas);
        MessagingFee memory inboundFee = hub.quoteSend(inbound, false);
        vm.prank(alice);
        hub.send{ value: inboundFee.nativeFee }(inbound, inboundFee, alice);

        try this.verifyPackets(HOME_EID, bytes32(uint256(uint160(address(adapter))))) {
            return true;
        } catch {
            return false;
        }
    }

    /// A contract recipient does its own bookkeeping on receipt, and `NativeOFTAdapter._credit` forwards
    /// all remaining gas to it. The raised floor exists to cover that.
    function test_nativeCredit_toContract_fitsNativeFloor() public {
        address recipient = address(new BookkeepingRecipient());
        assertTrue(
            _nativeCreditLands(recipient, NATIVE_ENFORCED_LZRECEIVE_GAS),
            "native floor is no longer enough for a contract recipient"
        );
    }

    /// Why the native pathway needs a floor of its own. At the ERC20 floor the same delivery runs out of
    /// gas and takes the whole lzReceive with it, and a retry re-runs the same recipient - so the transfer
    /// stays stuck until someone re-executes it by hand. Measured threshold sits between 150k and 180k.
    function test_nativeCredit_toContract_wouldFailAtErc20Floor() public {
        address recipient = address(new BookkeepingRecipient());
        assertFalse(
            _nativeCreditLands(recipient, ENFORCED_LZRECEIVE_GAS),
            "ERC20 floor now suffices; the separate native floor may no longer be needed"
        );
    }
}
