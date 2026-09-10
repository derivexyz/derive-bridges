// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";

import {IOFT, SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import {TokenOFT9} from "../../contracts/TokenOFT9.sol";

interface IDeriveOFTReceiver {
    function peers(uint32 eid) external view returns (bytes32);
    function owner() external view returns (address);
    function lockedAmount(uint32 eid) external view returns (uint256);
    function setPeer(uint32 eid, bytes32 peer) external;
}

interface ISafe {
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
    function nonce() external view returns (uint256);
    function approveHash(bytes32 hashToApprove) external;
    function getTransactionHash(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 _nonce
    ) external view returns (bytes32);
    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes calldata signatures
    ) external payable returns (bool);
}

/// @notice Runs the migration on a Derive fork: the real Safe executes the real freeze calldata through
///         `execTransaction`, then the frozen supply is seeded into a hub token.
/// @dev Only Derive is forked. `seed` never touches LayerZero, so its correctness does not depend on
///      which chain it runs on - the hub deployed here is a stand-in for the Ethereum one, present so
///      the amount taken from the frozen chain can be carried through to a real mint.
///
///      Point FREEZE_JSON at `lz:freeze:derive-solana` output and the emitted bytes are checked against
///      what this test executes.
contract MigrationTest is Test {
    uint32 internal constant SOLANA_EID = 30168;
    bytes32 internal constant ZERO_PEER = bytes32(0);

    address internal constant WSOL = 0xf9c53688EA88cca83e6fe0A0395CaF5E50E1FEA4;
    address internal constant WSOL_RECEIVER = 0xDFF82f3Fa7fC78134EB47b6da4da8020309F88b9;
    address internal constant JITOSOL = 0x457DAD393910532646E97ec529C33edBcBd9D4BA;
    address internal constant JITOSOL_RECEIVER = 0xA004E01B96BAcf6480eA47199148cBc210e82357;

    /// @dev EndpointV2 on Derive, for the stand-in hub. Not the same address as on Ethereum.
    address internal constant ENDPOINT_DERIVE = 0xcb566e3B6934Fa77258d68ea18E931fa75e1aaAa;

    uint256 internal constant DERIVE_CHAIN_ID = 957;

    /// @dev 3-of-5 Safe v1.4.1, owner of both receivers. Asserted against `owner()` rather than trusted.
    address internal constant DERIVE_SAFE = 0x169a99B9958386a5D91E732Ed08B344946A92391;

    /// @dev The batch `lz:freeze:derive-solana` writes, committed so it is reviewed in the diff.
    string internal constant FREEZE_BATCH = "multisig/freeze-derive-solana.json";

    address internal hubSafe = makeAddr("hubSafe");
    address internal distributor = makeAddr("distributor");

    bool internal forked;

    function setUp() public {
        forked = _tryFork("derive");
        if (!forked) return;

        // The rpc alias could point anywhere. Everything below reads mainnet Derive addresses, so a
        // different chain would assert against unrelated state.
        assertEq(block.chainid, DERIVE_CHAIN_ID, "the derive rpc endpoint is not Derive mainnet");
    }

    function _tryFork(string memory chainAlias) private returns (bool) {
        try vm.rpcUrl(chainAlias) returns (string memory url) {
            try vm.createSelectFork(url) returns (uint256) {
                return true;
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }

    function _freezeCalldata() private pure returns (bytes memory) {
        return abi.encodeCall(IDeriveOFTReceiver.setPeer, (SOLANA_EID, ZERO_PEER));
    }

    /**
     * The transaction the Safe should execute for `receiver`.
     *
     * Reads the committed batch, so the artifact the signers import is what the Safe executes here -
     * every run verifies the file itself rather than a reconstruction of it. FREEZE_JSON overrides the
     * path.
     *
     * A missing batch fails rather than falling back to locally built calldata: the file is committed,
     * so its absence means something is wrong, and a silent fallback would let this test pass while
     * checking nothing about the artifact.
     */
    function _freezeTx(uint256 index, address receiver) private view returns (bytes memory) {
        bytes memory expected = _freezeCalldata();

        string memory path = vm.envOr("FREEZE_JSON", string(FREEZE_BATCH));

        string memory json;
        try vm.readFile(path) returns (string memory contents) {
            json = contents;
        } catch {
            revert(string.concat("no Safe batch at ", path, "; regenerate with lz:freeze:derive-solana"));
        }
        string memory base = string.concat(".transactions[", vm.toString(index), "]");

        assertEq(vm.parseJsonString(json, ".chainId"), vm.toString(DERIVE_CHAIN_ID), "batch is for another chain");
        assertEq(
            vm.parseJsonAddress(json, string.concat(base, ".to")), receiver, "emitted tx targets the wrong contract"
        );
        assertEq(vm.parseJsonString(json, string.concat(base, ".value")), "0", "emitted tx sends value");

        bytes memory emitted = vm.parseJsonBytes(json, string.concat(base, ".data"));
        assertEq(emitted, expected, "emitted calldata differs from the expected encoding");

        return emitted;
    }

    /// Safe requires signatures ordered by ascending owner address.
    function _sortedOwners(address[] memory owners) private pure returns (address[] memory) {
        for (uint256 i = 1; i < owners.length; i++) {
            address current = owners[i];
            uint256 j = i;
            while (j > 0 && owners[j - 1] > current) {
                owners[j] = owners[j - 1];
                j--;
            }
            owners[j] = current;
        }
        return owners;
    }

    /**
     * Executes `data` through the real Safe, satisfying its real threshold.
     *
     * Uses on-chain hash approval rather than ECDSA, since the owners' keys are not available: each
     * signer calls `approveHash`, and the signature blob marks that with v=1. The Safe still checks the
     * threshold, the nonce and every signer, so this exercises `execTransaction` rather than bypassing it.
     */
    function _execViaSafe(address safeAddress, address to, bytes memory data) private {
        ISafe safe = ISafe(safeAddress);
        uint256 threshold = safe.getThreshold();
        address[] memory owners = _sortedOwners(safe.getOwners());
        assertGe(owners.length, threshold, "fewer owners than the threshold");

        uint256 nonceBefore = safe.nonce();
        bytes32 txHash = safe.getTransactionHash(
            to,
            0,
            data,
            0, // CALL
            0,
            0,
            0,
            address(0),
            address(0),
            nonceBefore
        );

        bytes memory signatures;
        for (uint256 i = 0; i < threshold; i++) {
            vm.prank(owners[i]);
            safe.approveHash(txHash);
            signatures = bytes.concat(signatures, bytes32(uint256(uint160(owners[i]))), bytes32(0), bytes1(0x01));
        }

        vm.prank(owners[0]);
        assertTrue(
            safe.execTransaction(to, 0, data, 0, 0, 0, 0, address(0), payable(address(0)), signatures),
            "Safe execTransaction failed"
        );

        // A consumed nonce is the Safe's own record that this went through execTransaction.
        assertEq(safe.nonce(), nonceBefore + 1, "Safe nonce did not advance");
    }

    /// @return outstanding Supply at the moment of the freeze - the amount the seed must reproduce.
    function _freezeViaSafe(uint256 index, address receiver, address token) private returns (uint256 outstanding) {
        IDeriveOFTReceiver oapp = IDeriveOFTReceiver(receiver);

        assertTrue(oapp.peers(SOLANA_EID) != ZERO_PEER, "already frozen, nothing to test");
        assertEq(oapp.owner(), DERIVE_SAFE, "receiver owner is not the expected Safe");

        _execViaSafe(DERIVE_SAFE, receiver, _freezeTx(index, receiver));

        assertEq(oapp.peers(SOLANA_EID), ZERO_PEER, "peer not cleared");

        // Quoting resolves the peer, so a revert here proves sending is now impossible - not merely
        // that a storage slot changed.
        SendParam memory sendParam = SendParam({
            dstEid: SOLANA_EID,
            to: bytes32(uint256(uint160(distributor))),
            amountLD: 1e6,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: "",
            oftCmd: ""
        });
        vm.expectRevert();
        IOFT(receiver).quoteSend(sendParam, false);

        outstanding = IERC20(token).totalSupply();

        // The receiver mints and burns rather than escrowing, so every token came through it from
        // Solana. If these disagree, totalSupply is not a safe seed amount.
        assertEq(oapp.lockedAmount(SOLANA_EID), outstanding, "lockedAmount and totalSupply diverged");
    }

    function _deployHub(string memory symbol) private returns (TokenOFT9 hub) {
        address implementation = address(new TokenOFT9(ENDPOINT_DERIVE));
        hub = TokenOFT9(
            address(
                new ERC1967Proxy(implementation, abi.encodeCall(TokenOFT9.initialize, (symbol, symbol, address(this))))
            )
        );
        hub.transferOwnership(hubSafe);

        assertEq(hub.totalSupply(), 0, "a fresh hub token must start empty");
        assertFalse(hub.seeded(), "a fresh hub token cannot be seeded");
        assertEq(hub.decimals(), 9, "hub decimals must match Derive's");
    }

    function _seed(TokenOFT9 hub, uint256 amount) private {
        vm.prank(hubSafe);
        hub.seed(distributor, amount);

        assertTrue(hub.seeded(), "seeded flag not set");
        assertEq(hub.totalSupply(), amount, "hub supply does not match the frozen Derive supply");
        assertEq(hub.balanceOf(distributor), amount, "seed did not reach the distributor");
    }

    function test_freezeThenSeed_viaSafe() public {
        if (!forked) return vm.skip(true);

        uint256 wsolOutstanding = _freezeViaSafe(0, WSOL_RECEIVER, WSOL);
        uint256 jitosolOutstanding = _freezeViaSafe(1, JITOSOL_RECEIVER, JITOSOL);

        assertGt(wsolOutstanding, 0, "nothing to migrate");
        assertGt(jitosolOutstanding, 0, "nothing to migrate");

        _seed(_deployHub("wSOL"), wsolOutstanding);
        _seed(_deployHub("jitoSOL"), jitosolOutstanding);
    }

    /// seed() is one-shot, which is why the amount has to be read after the freeze lands: a stale
    /// figure cannot be corrected by seeding again.
    function test_seed_cannotRunTwice() public {
        if (!forked) return vm.skip(true);

        TokenOFT9 hub = _deployHub("wSOL");
        _seed(hub, 1_000e9);

        vm.prank(hubSafe);
        vm.expectRevert(abi.encodeWithSignature("AlreadySeeded()"));
        hub.seed(distributor, 1);
    }

    function test_seed_onlyOwner() public {
        if (!forked) return vm.skip(true);

        TokenOFT9 hub = _deployHub("wSOL");

        vm.prank(distributor);
        vm.expectRevert();
        hub.seed(distributor, 1);
    }
}
