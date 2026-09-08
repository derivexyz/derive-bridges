// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IOFT, SendParam, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import { BridgeFixture } from "./BridgeFixture.sol";
import { TokenOFTAdapter } from "../../contracts/TokenOFTAdapter.sol";
import { StandInToken } from "../../contracts/testnet/StandInToken.sol";

/// @notice The hub mints at its home chain's decimals rather than defaulting to 18. Nothing reverts if
///         that is wrong - the token is simply misdenominated by orders of magnitude - so these are the
///         tests that hold the 18/9/6 split in place.
contract DecimalsTest is BridgeFixture {
    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");

    function setUp() public override {
        super.setUp();
        vm.deal(alice, 100 ether);
    }

    /// One whole token in must be the same integer out. That only holds when both sides agree on
    /// decimals; a hub left at 18 against a 6-decimal home would still round-trip, so comparing the
    /// raw integers is what actually catches the mistake.
    function _assertOneTokenCrossesIntact(uint8 _decimals) private {
        (IOFT hub, TokenOFTAdapter adapter, StandInToken token) = _deployPair(_decimals);

        uint256 one = 10 ** _decimals;
        token.mint(alice, one);

        SendParam memory sendParam = _sendParam(HUB_EID, bob, one, 200_000);
        MessagingFee memory fee = IOFT(address(adapter)).quoteSend(sendParam, false);

        vm.startPrank(alice);
        token.approve(address(adapter), one);
        IOFT(address(adapter)).send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        verifyPackets(HUB_EID, bytes32(uint256(uint160(address(hub)))));

        assertEq(IERC20Metadata(address(hub)).decimals(), token.decimals(), "hub and home decimals diverged");
        assertEq(IERC20(address(hub)).balanceOf(bob), one, "amount changed crossing the bridge");
        assertEq(token.balanceOf(address(adapter)), one, "escrow does not hold what was sent");
    }

    function test_oneToken_crossesIntact_18Decimals() public {
        _assertOneTokenCrossesIntact(18);
    }

    function test_oneToken_crossesIntact_9Decimals() public {
        _assertOneTokenCrossesIntact(9);
    }

    function test_oneToken_crossesIntact_6Decimals() public {
        _assertOneTokenCrossesIntact(6);
    }

    /// Every token the hub has minted must be matched by collateral sitting in the escrow. This is the
    /// property the whole bridge rests on, and the one worth monitoring in production.
    function testFuzz_escrowMatchesHubSupply(uint96 _rawAmount, uint8 _pick) public {
        uint8 decimals = [uint8(18), 9, 6][_pick % 3];
        (IOFT hub, TokenOFTAdapter adapter, StandInToken token) = _deployPair(decimals);

        uint256 amount = bound(uint256(_rawAmount), 1, _sharedDecimalsCeiling(decimals));
        token.mint(alice, amount);

        SendParam memory sendParam = _sendParam(HUB_EID, bob, amount, 200_000);
        MessagingFee memory fee = IOFT(address(adapter)).quoteSend(sendParam, false);

        vm.startPrank(alice);
        token.approve(address(adapter), amount);
        IOFT(address(adapter)).send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        verifyPackets(HUB_EID, bytes32(uint256(uint160(address(hub)))));

        assertEq(
            token.balanceOf(address(adapter)),
            IERC20(address(hub)).totalSupply(),
            "escrow and hub supply diverged"
        );
    }

    /// @dev The wire carries the shared amount as a uint64, so one transfer cannot exceed this.
    function _sharedDecimalsCeiling(uint8 _decimals) private pure returns (uint256) {
        return uint256(type(uint64).max) * (10 ** (_decimals - 6));
    }

    /// A single transfer above the uint64 shared-decimals ceiling reverts rather than truncating. That
    /// caps one transfer at ~18.4 trillion tokens, far above any of the five supplies here, but it is
    /// the constraint that would bite if sharedDecimals were ever raised.
    function test_amountAboveSharedDecimalsCeiling_reverts() public {
        (, TokenOFTAdapter adapter, StandInToken token) = _deployPair(9);

        uint256 amount = _sharedDecimalsCeiling(9) + 1e3;
        token.mint(alice, amount);

        SendParam memory sendParam = _sendParam(HUB_EID, bob, amount, 200_000);

        vm.prank(alice);
        token.approve(address(adapter), amount);

        vm.expectRevert(abi.encodeWithSignature("AmountSDOverflowed(uint256)", uint256(type(uint64).max) + 1));
        IOFT(address(adapter)).quoteSend(sendParam, false);
    }

    /// Amounts finer than sharedDecimals cannot cross. They must stay with the sender rather than being
    /// escrowed and silently dropped.
    function test_dustBelowSharedDecimals_staysWithSender() public {
        (IOFT hub, TokenOFTAdapter adapter, StandInToken token) = _deployPair(18);

        // sharedDecimals is 6, so at 18 local decimals anything under 1e12 is dust.
        uint256 amount = 1e18 + 999;
        token.mint(alice, amount);

        SendParam memory sendParam = _sendParam(HUB_EID, bob, amount, 200_000);
        MessagingFee memory fee = IOFT(address(adapter)).quoteSend(sendParam, false);

        vm.startPrank(alice);
        token.approve(address(adapter), amount);
        IOFT(address(adapter)).send{ value: fee.nativeFee }(sendParam, fee, alice);
        vm.stopPrank();

        verifyPackets(HUB_EID, bytes32(uint256(uint160(address(hub)))));

        assertEq(token.balanceOf(alice), 999, "dust was taken from the sender");
        assertEq(token.balanceOf(address(adapter)), 1e18, "dust was escrowed");
        assertEq(IERC20(address(hub)).balanceOf(bob), 1e18, "dust crossed the bridge");
    }
}
