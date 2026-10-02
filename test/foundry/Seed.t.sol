// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { BridgeFixture } from "./BridgeFixture.sol";
import { OFTToken } from "../../contracts/OFTToken.sol";
import { OFTTokenSeeded, OFTToken9Seeded } from "../../contracts/OFTTokenSeeded.sol";

/// @notice The seeded hub, driven through a proxy as it will be in production. Migration.t.sol covers
///         the same calls against the real frozen supply, but only when a Derive fork is reachable;
///         this holds the contract's own rules offline.
contract SeedTest is BridgeFixture {
    address private safe = makeAddr("safe");
    address private distributor = makeAddr("distributor");

    event Seeded(address indexed to, uint256 amount);

    function _deploySeededHub() private returns (OFTToken9Seeded hub) {
        address impl = address(new OFTToken9Seeded(address(endpoints[HUB_EID])));
        hub = OFTToken9Seeded(
            address(new ERC1967Proxy(impl, abi.encodeCall(OFTToken.initialize, ("wSOL", "wSOL", address(this)))))
        );
        hub.transferOwnership(safe);
    }

    function test_freshHub_isEmptyAndUnseeded() public {
        OFTToken9Seeded hub = _deploySeededHub();

        assertEq(hub.decimals(), 9);
        assertEq(hub.decimalConversionRate(), 1e3);
        assertEq(hub.totalSupply(), 0, "a fresh hub must start empty");
        assertFalse(hub.seeded());
    }

    function test_seed_mintsOnce() public {
        OFTToken9Seeded hub = _deploySeededHub();

        vm.expectEmit(address(hub));
        emit Seeded(distributor, 1_000e9);
        vm.prank(safe);
        hub.seed(distributor, 1_000e9);

        assertTrue(hub.seeded());
        assertEq(hub.totalSupply(), 1_000e9);
        assertEq(hub.balanceOf(distributor), 1_000e9);

        vm.prank(safe);
        vm.expectRevert(OFTTokenSeeded.AlreadySeeded.selector);
        hub.seed(distributor, 1);
    }

    function test_seed_onlyOwner() public {
        OFTToken9Seeded hub = _deploySeededHub();

        vm.prank(distributor);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", distributor));
        hub.seed(distributor, 1);
    }

    /// The bare implementation locks its initializer, so nothing can be seeded outside a proxy.
    function test_implementation_cannotBeInitialized() public {
        OFTToken9Seeded impl = new OFTToken9Seeded(address(endpoints[HUB_EID]));

        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        impl.initialize("wSOL", "wSOL", address(this));
    }
}
