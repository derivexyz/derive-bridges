// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";

import { TransferBridgeRoles, IOApp, IEndpointDelegates, IProxyAdmin, ISafe } from "../../script/TransferBridgeRoles.s.sol";

/// @notice Runs script/TransferBridgeRoles.s.sol against a fork of each mainnet chain and checks that
///         every role moved, that nothing else about the proxies changed, and that the deployer is
///         locked out afterwards while the Safe is not.
///
///         Discovery reads deployments/ on disk, so each chain's result is pinned here to the explicit
///         list from mainnet-bridges.json plus the WETH pathway it omits. A deployment added to the
///         directory without being added here fails the test rather than being transferred unseen. The
///         script's hold-back list is pinned the same way, and held-back bridges are checked to be untouched.
/// @dev Skips rather than fails when a fork is unreachable, so the suite still runs offline.
contract TransferBridgeRolesTest is Test {
    address internal constant NEW_OWNER = 0x62c004a89EDBd7bECBdf54E14779B7e7F5b390F7;

    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error OwnableUnauthorizedAccount(address account);

    struct Expected {
        string name;
        address proxy;
        address proxyAdmin;
    }

    function test_ethereum() public {
        Expected[] memory expected = new Expected[](6);
        expected[0] = Expected(
            "CBBTC",
            0x2e3023ca882Ee359EBfa69b740bE318dF1B5cD7c,
            0xFc1eEf04611187E13602c1B1160C1e6586801c24
        );
        expected[1] = Expected(
            "HYPE",
            0x0762365e088Fb8D285b295d782BB7b23690713e2,
            0x4e12aE307FF151f22F2c4126644e1daD1CA58aB1
        );
        expected[2] = Expected(
            "FXRP",
            0x13FD17b60735Be034b874E31Ef4aeD2cd613c9F9,
            0xA61df3c0A8509Cfb1d20225e3c3663b8D6806152
        );
        expected[3] = Expected(
            "SOL",
            0xb5EaD284CD00fD0EB37E84327a4ee781172A07D6,
            0x3C8e1dADe84091aE00FEeDB8745C397CFFAe1390
        );
        expected[4] = Expected(
            "JITOSOL",
            0xc2908Db337AA16fB22b01bd4e8fF91460b23fF4B,
            0xF6e11C5AAAcA6527CF635D257EAA9a93C8164a43
        );
        expected[5] = Expected(
            "WETH",
            0xD903EE77c30d435f0d833b084eD878eA0F85737E,
            0xBF574008B5D007295d4098375F379B1637588276
        );
        // SOL and jitoSOL stay with the deployer for now.
        string[] memory heldBack = new string[](2);
        heldBack[0] = "SOL";
        heldBack[1] = "JITOSOL";
        _runOn("ethereum", 1, expected, heldBack);
    }

    function test_base() public {
        Expected[] memory expected = new Expected[](2);
        expected[0] = Expected(
            "CBBTC_Adapter",
            0x0eCA5fA53b2951F78E916C9B29F45C8D909F1cb2,
            0xD49956993FA4a3a7c8F356B71f1d331Bfb3210C5
        );
        expected[1] = Expected(
            "WETH_Adapter",
            0x591382db5d153BE499e9b9694b4fB43530f2FeE7,
            0xeDD8061207e7362f48B3Cb4ef434ECb8dc7e99C0
        );
        _runOn("base", 8453, expected, new string[](0));
    }

    function test_hyperevm() public {
        Expected[] memory expected = new Expected[](1);
        expected[0] = Expected(
            "HYPE_Adapter",
            0x1E0470Ef72d029Bdc87D3B8543Fb62fc04db9670,
            0xb1178803A726e2077947754de9f2f0cbdA29A60F
        );
        _runOn("hyperevm", 999, expected, new string[](0));
    }

    function test_flare() public {
        Expected[] memory expected = new Expected[](1);
        expected[0] = Expected(
            "FXRP_Adapter",
            0x8F8c29B0271D4c60435DaF148df4a84edcB21c98,
            0xF982c812099d03AFFa0c8062aa1abcb584c23329
        );
        _runOn("flare", 14, expected, new string[](0));
    }

    /// Anyone other than the owner gets a clear revert before anything is touched.
    function test_ethereum_rejectsWrongSender() public {
        if (!_forked("ethereum")) return vm.skip(true);

        TransferBridgeRoles script = new TransferBridgeRoles();
        TransferBridgeRoles.Bridge[] memory bridges = script.discover(block.chainid);
        address deployer = IOApp(bridges[0].proxy).owner();

        vm.expectRevert();
        script.runAs(makeAddr("stranger"));

        for (uint256 i = 0; i < bridges.length; i++) {
            assertEq(IOApp(bridges[i].proxy).owner(), deployer, "owner changed despite the revert");
            assertEq(
                IProxyAdmin(bridges[i].proxyAdmin).owner(),
                deployer,
                "ProxyAdmin owner changed despite the revert"
            );
        }
    }

    function _runOn(
        string memory _chainAlias,
        uint256 _chainId,
        Expected[] memory _expected,
        string[] memory _heldBack
    ) private {
        if (!_forked(_chainAlias)) return vm.skip(true);
        assertEq(block.chainid, _chainId, "rpc alias points at another chain");

        TransferBridgeRoles script = new TransferBridgeRoles();
        TransferBridgeRoles.Bridge[] memory bridges = script.discover(_chainId);
        _assertDiscoveryMatches(bridges, _expected);
        for (uint256 i = 0; i < bridges.length; i++) {
            assertEq(
                script.isHeldBack(bridges[i].name),
                _isIn(_heldBack, bridges[i].name),
                string.concat(bridges[i].name, ": script's hold-back list differs from the test's")
            );
        }

        // The Safe the roles go to has to exist here and be able to sign.
        assertGt(NEW_OWNER.code.length, 0, "Safe has no code on this chain");
        assertGt(ISafe(NEW_OWNER).getThreshold(), 0, "Safe threshold is zero");

        // Everything starts with one deployer holding all three roles, so there is one sender to run as.
        address deployer = IOApp(bridges[0].proxy).owner();
        assertTrue(deployer != NEW_OWNER, "already transferred: nothing to test");
        bytes32[] memory implementations = new bytes32[](bridges.length);
        for (uint256 i = 0; i < bridges.length; i++) {
            assertEq(
                IOApp(bridges[i].proxy).owner(),
                deployer,
                string.concat(bridges[i].name, ": owner is not the deployer")
            );
            assertEq(
                _delegateOf(bridges[i].proxy),
                deployer,
                string.concat(bridges[i].name, ": delegate is not the deployer")
            );
            assertEq(
                IProxyAdmin(bridges[i].proxyAdmin).owner(),
                deployer,
                string.concat(bridges[i].name, ": ProxyAdmin owner is not the deployer")
            );
            implementations[i] = vm.load(bridges[i].proxy, IMPLEMENTATION_SLOT);
        }

        script.runAs(deployer);

        for (uint256 i = 0; i < bridges.length; i++) {
            _assertRolesHeldBy(bridges[i], _isIn(_heldBack, bridges[i].name) ? deployer : NEW_OWNER);
            // Only who controls the proxy changed, not what it points at or who administers it.
            assertEq(
                vm.load(bridges[i].proxy, IMPLEMENTATION_SLOT),
                implementations[i],
                string.concat(bridges[i].name, ": implementation changed")
            );
            assertEq(
                address(uint160(uint256(vm.load(bridges[i].proxy, ADMIN_SLOT)))),
                bridges[i].proxyAdmin,
                string.concat(bridges[i].name, ": proxy admin changed")
            );
        }

        // A second run finds nothing to do and does not revert.
        script.runAs(deployer);
        for (uint256 i = 0; i < bridges.length; i++) {
            _assertRolesHeldBy(bridges[i], _isIn(_heldBack, bridges[i].name) ? deployer : NEW_OWNER);
        }

        // Control actually moved: the Safe can exercise each role and the deployer no longer can. A
        // held-back bridge is the other way round.
        for (uint256 i = 0; i < bridges.length; i++) {
            IOApp oapp = IOApp(bridges[i].proxy);
            IProxyAdmin proxyAdmin = IProxyAdmin(bridges[i].proxyAdmin);

            if (_isIn(_heldBack, bridges[i].name)) {
                vm.prank(deployer);
                oapp.setDelegate(deployer);
                vm.prank(deployer);
                proxyAdmin.transferOwnership(deployer);
                continue;
            }

            vm.prank(NEW_OWNER);
            oapp.setDelegate(NEW_OWNER);
            vm.prank(NEW_OWNER);
            proxyAdmin.transferOwnership(NEW_OWNER);

            vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, deployer));
            vm.prank(deployer);
            oapp.setDelegate(deployer);

            // hardhat-deploy's ProxyAdmin is OpenZeppelin v4, which reverts with a string.
            vm.expectRevert(bytes("Ownable: caller is not the owner"));
            vm.prank(deployer);
            proxyAdmin.transferOwnership(deployer);
        }
    }

    function _assertRolesHeldBy(TransferBridgeRoles.Bridge memory _bridge, address _holder) private view {
        string memory who = vm.toString(_holder);
        assertEq(IOApp(_bridge.proxy).owner(), _holder, string.concat(_bridge.name, ": owner is not ", who));
        assertEq(_delegateOf(_bridge.proxy), _holder, string.concat(_bridge.name, ": delegate is not ", who));
        assertEq(
            IProxyAdmin(_bridge.proxyAdmin).owner(),
            _holder,
            string.concat(_bridge.name, ": ProxyAdmin owner is not ", who)
        );
    }

    function _isIn(string[] memory _list, string memory _name) private pure returns (bool) {
        for (uint256 i = 0; i < _list.length; i++) {
            if (keccak256(bytes(_list[i])) == keccak256(bytes(_name))) return true;
        }
        return false;
    }

    function _assertDiscoveryMatches(
        TransferBridgeRoles.Bridge[] memory _found,
        Expected[] memory _expected
    ) private pure {
        assertEq(_found.length, _expected.length, "deployments/ holds a different number of bridges than expected");
        for (uint256 i = 0; i < _expected.length; i++) {
            bool matched;
            for (uint256 j = 0; j < _found.length; j++) {
                if (keccak256(bytes(_found[j].name)) != keccak256(bytes(_expected[i].name))) continue;
                assertEq(
                    _found[j].proxy,
                    _expected[i].proxy,
                    string.concat(_expected[i].name, ": proxy address differs")
                );
                assertEq(
                    _found[j].proxyAdmin,
                    _expected[i].proxyAdmin,
                    string.concat(_expected[i].name, ": ProxyAdmin address differs")
                );
                matched = true;
            }
            assertTrue(matched, string.concat(_expected[i].name, ": not found in deployments/"));
        }
    }

    function _delegateOf(address _oapp) private view returns (address) {
        return IEndpointDelegates(IOApp(_oapp).endpoint()).delegates(_oapp);
    }

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
}
