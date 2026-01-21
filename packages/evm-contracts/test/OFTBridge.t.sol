// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/OFTSourceAdapter.sol";
import "../src/OFTDestination.sol";
import "../src/mocks/MockERC20.sol";

/**
 * @title OFTBridgeTest
 * @dev Forge tests for the OFT bridge contracts
 * @dev Tests the many-to-one architecture with liquidity tracking
 */
contract OFTBridgeTest is Test {
    OFTSourceAdapter public sourceAdapter1;
    OFTSourceAdapter public sourceAdapter2;
    OFTDestination public destination;
    MockERC20 public token1;
    MockERC20 public token2;

    address public owner;
    address public user1;
    address public user2;
    address public lzEndpoint;

    uint32 constant DESTINATION_EID = 1;
    uint32 constant SOURCE_EID_1 = 101;
    uint32 constant SOURCE_EID_2 = 102;

    uint256 constant INITIAL_MINT = 1_000_000 ether;

    event ChainLiquidityUpdated(uint32 indexed srcEid, uint256 newLiquidity);
    event Paused(bool paused);

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        lzEndpoint = makeAddr("lzEndpoint");

        // Deploy mock tokens
        token1 = new MockERC20("Source Token 1", "SRC1");
        token2 = new MockERC20("Source Token 2", "SRC2");

        // Deploy destination OFT
        destination = new OFTDestination(lzEndpoint);
        destination.initialize("Canonical Token", "CTKN", owner, 0); // No supply cap

        // Deploy source adapters
        sourceAdapter1 = new OFTSourceAdapter(address(token1), lzEndpoint, DESTINATION_EID);
        sourceAdapter1.initialize(owner);

        sourceAdapter2 = new OFTSourceAdapter(address(token2), lzEndpoint, DESTINATION_EID);
        sourceAdapter2.initialize(owner);

        // Fund users
        token1.mint(user1, INITIAL_MINT);
        token2.mint(user2, INITIAL_MINT);
    }

    function testDeployment() public view {
        // Test destination
        assertEq(destination.name(), "Canonical Token");
        assertEq(destination.symbol(), "CTKN");
        assertEq(destination.owner(), owner);
        assertEq(destination.supplyCap(), 0);
        assertFalse(destination.paused());

        // Test source adapters
        assertEq(sourceAdapter1.destinationEid(), DESTINATION_EID);
        assertEq(sourceAdapter1.token(), address(token1));
        assertFalse(sourceAdapter1.paused());

        assertEq(sourceAdapter2.destinationEid(), DESTINATION_EID);
        assertEq(sourceAdapter2.token(), address(token2));
    }

    function testDestinationCreditIncreasesLiquidity() public {
        uint256 amount = 100 ether;

        // Simulate receiving from source chain 1
        vm.expectEmit(true, false, false, true);
        emit ChainLiquidityUpdated(SOURCE_EID_1, amount);

        vm.prank(lzEndpoint);
        destination._credit(user1, amount, SOURCE_EID_1);

        assertEq(destination.balanceOf(user1), amount);
        assertEq(destination.getChainLiquidity(SOURCE_EID_1), amount);
    }

    function testDestinationTracksSeparateLiquidityPerChain() public {
        uint256 amount1 = 100 ether;
        uint256 amount2 = 200 ether;

        // Receive from chain 1
        vm.prank(lzEndpoint);
        destination._credit(user1, amount1, SOURCE_EID_1);

        // Receive from chain 2
        vm.prank(lzEndpoint);
        destination._credit(user2, amount2, SOURCE_EID_2);

        // Check liquidity is tracked separately
        assertEq(destination.getChainLiquidity(SOURCE_EID_1), amount1);
        assertEq(destination.getChainLiquidity(SOURCE_EID_2), amount2);
        assertEq(destination.totalSupply(), amount1 + amount2);
    }

    function testDestinationDebitDecreasesLiquidity() public {
        uint256 creditAmount = 100 ether;
        uint256 debitAmount = 50 ether;

        // First credit to add liquidity
        vm.prank(lzEndpoint);
        destination._credit(user1, creditAmount, SOURCE_EID_1);

        uint256 liquidityBefore = destination.getChainLiquidity(SOURCE_EID_1);
        assertEq(liquidityBefore, creditAmount);

        // Now debit (send back to source)
        vm.expectEmit(true, false, false, true);
        emit ChainLiquidityUpdated(SOURCE_EID_1, creditAmount - debitAmount);

        vm.prank(user1);
        destination._debit(user1, debitAmount, debitAmount, SOURCE_EID_1);

        assertEq(destination.getChainLiquidity(SOURCE_EID_1), creditAmount - debitAmount);
        assertEq(destination.balanceOf(user1), creditAmount - debitAmount);
    }

    function testDestinationRevertsOnInsufficientLiquidity() public {
        uint256 creditAmount = 100 ether;
        uint256 debitAmount = 150 ether;

        // Credit some tokens
        vm.prank(lzEndpoint);
        destination._credit(user1, creditAmount, SOURCE_EID_1);

        // Try to debit more than available liquidity
        vm.prank(user1);
        vm.expectRevert("OFTDestination: insufficient liquidity on destination chain");
        destination._debit(user1, debitAmount, debitAmount, SOURCE_EID_1);
    }

    function testDestinationPreventsWithdrawalToChainWithoutLiquidity() public {
        uint256 amount = 100 ether;

        // Credit from chain 1
        vm.prank(lzEndpoint);
        destination._credit(user1, amount, SOURCE_EID_1);

        // Try to send to chain 2 (which has no liquidity)
        vm.prank(user1);
        vm.expectRevert("OFTDestination: insufficient liquidity on destination chain");
        destination._debit(user1, amount, amount, SOURCE_EID_2);
    }

    function testDestinationSupplyCap() public {
        uint256 cap = 1000 ether;

        // Deploy with supply cap
        OFTDestination cappedDestination = new OFTDestination(lzEndpoint);
        cappedDestination.initialize("Capped Token", "CTKN", owner, cap);

        // Credit up to cap
        vm.prank(lzEndpoint);
        cappedDestination._credit(user1, cap, SOURCE_EID_1);

        // Try to exceed cap
        vm.prank(lzEndpoint);
        vm.expectRevert("OFTDestination: supply cap exceeded");
        cappedDestination._credit(user1, 1, SOURCE_EID_1);
    }

    function testDestinationPause() public {
        uint256 amount = 100 ether;

        // Pause the contract
        vm.expectEmit(false, false, false, true);
        emit Paused(true);
        destination.setPaused(true);

        assertTrue(destination.paused());

        // Try to credit when paused
        vm.prank(lzEndpoint);
        vm.expectRevert("OFTDestination: paused");
        destination._credit(user1, amount, SOURCE_EID_1);

        // Unpause
        destination.setPaused(false);
        assertFalse(destination.paused());

        // Should work now
        vm.prank(lzEndpoint);
        destination._credit(user1, amount, SOURCE_EID_1);
        assertEq(destination.balanceOf(user1), amount);
    }

    function testSourceAdapterPause() public {
        // Pause the adapter
        vm.expectEmit(false, false, false, true);
        emit Paused(true);
        sourceAdapter1.setPaused(true);

        assertTrue(sourceAdapter1.paused());

        // Unpause
        sourceAdapter1.setPaused(false);
        assertFalse(sourceAdapter1.paused());
    }

    function testOnlyOwnerCanPause() public {
        vm.prank(user1);
        vm.expectRevert();
        destination.setPaused(true);

        vm.prank(user1);
        vm.expectRevert();
        sourceAdapter1.setPaused(true);
    }

    function testOnlyOwnerCanSetSupplyCap() public {
        vm.prank(user1);
        vm.expectRevert();
        destination.setSupplyCap(1000 ether);
    }

    function testHasSufficientLiquidity() public {
        uint256 amount = 100 ether;

        // Initially no liquidity
        assertFalse(destination.hasSufficientLiquidity(SOURCE_EID_1, amount));

        // Add liquidity
        vm.prank(lzEndpoint);
        destination._credit(user1, amount, SOURCE_EID_1);

        // Now has liquidity
        assertTrue(destination.hasSufficientLiquidity(SOURCE_EID_1, amount));
        assertTrue(destination.hasSufficientLiquidity(SOURCE_EID_1, amount - 1));
        assertFalse(destination.hasSufficientLiquidity(SOURCE_EID_1, amount + 1));
    }

    function testMultipleUsersCanBridge() public {
        uint256 amount1 = 100 ether;
        uint256 amount2 = 200 ether;

        // User1 bridges from chain 1
        vm.prank(lzEndpoint);
        destination._credit(user1, amount1, SOURCE_EID_1);

        // User2 bridges from chain 1
        vm.prank(lzEndpoint);
        destination._credit(user2, amount2, SOURCE_EID_1);

        assertEq(destination.balanceOf(user1), amount1);
        assertEq(destination.balanceOf(user2), amount2);
        assertEq(destination.getChainLiquidity(SOURCE_EID_1), amount1 + amount2);
    }

    function testLiquidityTracking_FuzzTest(uint96 amount) public {
        vm.assume(amount > 0);

        // Credit
        vm.prank(lzEndpoint);
        destination._credit(user1, amount, SOURCE_EID_1);
        assertEq(destination.getChainLiquidity(SOURCE_EID_1), amount);

        // Debit half
        uint256 debitAmount = amount / 2;
        vm.prank(user1);
        destination._debit(user1, debitAmount, debitAmount, SOURCE_EID_1);
        assertEq(destination.getChainLiquidity(SOURCE_EID_1), amount - debitAmount);
    }
}
