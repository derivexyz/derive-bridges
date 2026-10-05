// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { Script } from "forge-std/Script.sol";
import { Vm } from "forge-std/Vm.sol";
import { console2 } from "forge-std/console2.sol";

interface IOApp {
    function owner() external view returns (address);
    function endpoint() external view returns (address);
    function setDelegate(address _delegate) external;
    function transferOwnership(address _newOwner) external;
}

interface IEndpointDelegates {
    function delegates(address _oapp) external view returns (address);
}

interface IProxyAdmin {
    function owner() external view returns (address);
    function transferOwnership(address _newOwner) external;
}

interface ISafe {
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
}

/// @notice Hands every privileged role on this chain's bridge contracts to the Safe.
///
///         Each bridge contract carries three roles, all held by the deployer EOA today:
///           - the OApp owner: peers, enforced options, delegate, and `seed` on the seeded hub tokens;
///           - the delegate registered on the LayerZero endpoint: libraries, DVN config, skip/nilify/burn;
///           - the owner of the ProxyAdmin behind the TransparentUpgradeableProxy: upgrades.
///         The proxy's admin stays the ProxyAdmin contract. Only who owns that ProxyAdmin changes.
///
///         Which contracts: read from hardhat-deploy's `deployments/<network>/` for whichever chain the
///         script is run against (matched on `.chainId`), one bridge per `<Name>_ProxyAdmin.json`. So
///         nothing deployed is missed and nothing is listed twice; the log names every contract found.
///         test/foundry/TransferBridgeRoles.t.sol pins that discovery to an explicit list per chain.
///
///         Deployments named in `isHeldBack` are inventoried and logged but left with the current owner.
///         SOL and jitoSOL are held back for now; remove them there when they are ready to go to the Safe.
///
///         Order matters: `setDelegate` is owner-only, so it runs before `transferOwnership`. Idempotent:
///         a role the Safe already holds is skipped, so a partial run can simply be repeated.
///
/// @dev    chainwrap injects the deployer key, which is not the owner, so name the sender yourself.
///         Dry run:   forge-l1 script script/TransferBridgeRoles.s.sol --sender <owner> --unlocked
///         Broadcast: forge-l1 script script/TransferBridgeRoles.s.sol --private-key "$PRIVATE_KEY" --broadcast
///         (PRIVATE_KEY from .env.mainnet is the owner's.) Same for forge-base, forge-hyperevm, forge-flare.
contract TransferBridgeRoles is Script {
    address public constant NEW_OWNER = 0x62c004a89EDBd7bECBdf54E14779B7e7F5b390F7;

    /// @dev ERC-1967 admin slot. Checked against the ProxyAdmin the deployment names, since transferring
    ///      a ProxyAdmin that does not administer the proxy would hand over nothing.
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    string internal constant DEPLOYMENTS_DIR = "deployments";
    string internal constant PROXY_ADMIN_SUFFIX = "_ProxyAdmin.json";

    struct Bridge {
        string name;
        address proxy;
        address proxyAdmin;
    }

    function run() external {
        _execute(msg.sender, true);
    }

    /// @notice Deployments left with the current owner for now. Logged on every run so they are not forgotten.
    function isHeldBack(string memory _name) public pure returns (bool) {
        bytes32 name = keccak256(bytes(_name));
        return name == keccak256("SOL") || name == keccak256("JITOSOL");
    }

    /// @notice The same transfer, pranked rather than broadcast, for fork tests.
    function runAs(address _sender) external {
        _execute(_sender, false);
    }

    function _execute(address _sender, bool _broadcast) internal {
        _checkNewOwner();

        Bridge[] memory bridges = discover(block.chainid);
        require(bridges.length > 0, "no bridges found in deployments for this chain");
        console2.log("chain %s: %s bridge contract(s), sender %s", block.chainid, bridges.length, _sender);
        console2.log("sender balance: %s wei", _sender.balance);

        if (_broadcast) vm.startBroadcast(_sender);
        else vm.startPrank(_sender);

        uint256 transferred;
        for (uint256 i = 0; i < bridges.length; i++) {
            if (isHeldBack(bridges[i].name)) {
                console2.log("%s %s: held back, left with the current owner", bridges[i].name, bridges[i].proxy);
                continue;
            }
            _transfer(bridges[i], _sender);
            transferred++;
        }

        if (_broadcast) vm.stopBroadcast();
        else vm.stopPrank();

        require(transferred > 0, "every bridge on this chain is held back: nothing to do");
        for (uint256 i = 0; i < bridges.length; i++) {
            if (isHeldBack(bridges[i].name)) continue;
            _assertTransferred(bridges[i]);
        }
        console2.log("done: every role on %s of %s contract(s) is held by %s", transferred, bridges.length, NEW_OWNER);
    }

    /// Ownership transfer is single-step, so a wrong address here is unrecoverable. The target must at
    /// least be a Safe that exists on this chain and can sign.
    function _checkNewOwner() internal view {
        require(NEW_OWNER.code.length > 0, "new owner has no code on this chain: is the Safe deployed here?");

        ISafe safe = ISafe(NEW_OWNER);
        uint256 threshold = safe.getThreshold();
        address[] memory owners = safe.getOwners();
        require(threshold > 0 && owners.length >= threshold, "new owner is not a working Safe");

        console2.log("new owner %s is a Safe, threshold %s of %s:", NEW_OWNER, threshold, owners.length);
        for (uint256 i = 0; i < owners.length; i++) {
            console2.log("  signer %s", owners[i]);
        }
    }

    function _transfer(Bridge memory _bridge, address _sender) internal {
        IOApp oapp = IOApp(_bridge.proxy);
        IProxyAdmin proxyAdmin = IProxyAdmin(_bridge.proxyAdmin);
        IEndpointDelegates endpoint = IEndpointDelegates(oapp.endpoint());

        require(
            address(uint160(uint256(vm.load(_bridge.proxy, ADMIN_SLOT)))) == _bridge.proxyAdmin,
            string.concat(_bridge.name, ": proxy is not administered by the ProxyAdmin in its deployment")
        );

        address owner = oapp.owner();
        address delegate = endpoint.delegates(_bridge.proxy);
        address proxyAdminOwner = proxyAdmin.owner();

        console2.log("%s %s", _bridge.name, _bridge.proxy);
        console2.log("  owner %s  delegate %s", owner, delegate);
        console2.log("  proxyAdmin %s owned by %s", _bridge.proxyAdmin, proxyAdminOwner);

        if (owner != NEW_OWNER) {
            require(owner == _sender, string.concat(_bridge.name, ": sender is not the owner"));
            if (delegate != NEW_OWNER) {
                oapp.setDelegate(NEW_OWNER);
                console2.log("  -> setDelegate");
            }
            oapp.transferOwnership(NEW_OWNER);
            console2.log("  -> transferOwnership");
        } else if (delegate != NEW_OWNER) {
            // Ownership already moved, so only the Safe can re-point the delegate. Loud rather than
            // skipped: a stale delegate keeps control of the endpoint config.
            revert(
                string.concat(_bridge.name, ": owned by the Safe but the delegate is not; setDelegate from the Safe")
            );
        } else {
            console2.log("  owner and delegate already transferred");
        }

        if (proxyAdminOwner != NEW_OWNER) {
            require(proxyAdminOwner == _sender, string.concat(_bridge.name, ": sender does not own the ProxyAdmin"));
            proxyAdmin.transferOwnership(NEW_OWNER);
            console2.log("  -> ProxyAdmin.transferOwnership");
        } else {
            console2.log("  ProxyAdmin already transferred");
        }
    }

    function _assertTransferred(Bridge memory _bridge) internal view {
        IOApp oapp = IOApp(_bridge.proxy);
        require(oapp.owner() == NEW_OWNER, string.concat(_bridge.name, ": owner not transferred"));
        require(
            IEndpointDelegates(oapp.endpoint()).delegates(_bridge.proxy) == NEW_OWNER,
            string.concat(_bridge.name, ": delegate not transferred")
        );
        require(
            IProxyAdmin(_bridge.proxyAdmin).owner() == NEW_OWNER,
            string.concat(_bridge.name, ": ProxyAdmin owner not transferred")
        );
    }

    // ---- discovery ----------------------------------------------------------------------------------

    /// @notice Every proxied bridge contract hardhat-deploy recorded for `_chainId`.
    function discover(uint256 _chainId) public view returns (Bridge[] memory bridges) {
        string memory dir = deploymentsDirFor(_chainId);
        Vm.DirEntry[] memory entries = vm.readDir(dir);

        bridges = new Bridge[](entries.length);
        uint256 count;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].isDir || !_endsWith(entries[i].path, PROXY_ADMIN_SUFFIX)) continue;

            string memory file = _basename(entries[i].path);
            string memory name = _stripSuffix(file, PROXY_ADMIN_SUFFIX);

            bridges[count++] = Bridge({
                name: name,
                proxy: _deployedAddress(string.concat(dir, "/", name, ".json")),
                proxyAdmin: _deployedAddress(entries[i].path)
            });
        }

        assembly {
            mstore(bridges, count)
        }
    }

    /// @notice The `deployments/<network>` directory whose `.chainId` is `_chainId`.
    function deploymentsDirFor(uint256 _chainId) public view returns (string memory) {
        string memory wanted = vm.toString(_chainId);
        Vm.DirEntry[] memory entries = vm.readDir(DEPLOYMENTS_DIR);

        for (uint256 i = 0; i < entries.length; i++) {
            if (!entries[i].isDir) continue;
            string memory idFile = string.concat(entries[i].path, "/.chainId");
            if (!vm.exists(idFile)) continue;
            if (keccak256(bytes(vm.trim(vm.readFile(idFile)))) == keccak256(bytes(wanted))) {
                return entries[i].path;
            }
        }
        revert(string.concat("no deployments directory with .chainId ", wanted));
    }

    function _deployedAddress(string memory _path) internal view returns (address) {
        return vm.parseJsonAddress(vm.readFile(_path), ".address");
    }

    function _endsWith(string memory _s, string memory _suffix) internal pure returns (bool) {
        bytes memory s = bytes(_s);
        bytes memory suffix = bytes(_suffix);
        if (suffix.length > s.length) return false;
        for (uint256 i = 0; i < suffix.length; i++) {
            if (s[s.length - suffix.length + i] != suffix[i]) return false;
        }
        return true;
    }

    function _stripSuffix(string memory _s, string memory _suffix) internal pure returns (string memory) {
        bytes memory s = bytes(_s);
        bytes memory out = new bytes(s.length - bytes(_suffix).length);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = s[i];
        }
        return string(out);
    }

    function _basename(string memory _path) internal pure returns (string memory) {
        bytes memory p = bytes(_path);
        uint256 start;
        for (uint256 i = 0; i < p.length; i++) {
            if (p[i] == "/") start = i + 1;
        }
        bytes memory out = new bytes(p.length - start);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = p[start + i];
        }
        return string(out);
    }
}
