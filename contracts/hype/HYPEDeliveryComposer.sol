// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { IOFT } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

interface IWrappedNative is IERC20 {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

interface ICoreWriter {
    function sendRawAction(bytes calldata data) external;
}

struct SpotBalance {
    uint64 total;
    uint64 hold;
    uint64 entryNtl;
}

struct CoreUserExists {
    bool exists;
}

/// @notice Delivers bridged HYPE either as native HYPE on HyperEVM or into a HyperCore account.
/// @dev Set as `sendParam.to`, with `composeMsg` holding the recipient and the choice of the two.
///      Delivering here rather than in the adapter keeps a failure from reverting `lzReceive` and
///      sticking the transfer. Core addresses and the two-step deposit follow LayerZero's
///      HyperLiquidComposer, which cannot serve this bridge: it forwards the OFT's own ERC20 to a
///      `0x20..index` bridge, while HYPE is native and uses its own.
contract HYPEDeliveryComposer is IOAppComposer {
    using SafeERC20 for IERC20;

    error OnlyEndpoint(address caller);
    error OnlySelf(address caller);
    error UnexpectedOFT(address oft);
    error MalformedComposeMsg(uint256 length);
    error UnscalableAmount(uint256 amountLD);
    error CoreUserNotActivated(address to);
    error AssetBridgeUnderfunded(uint256 requested, uint64 available);
    error NativeTransferFailed(uint256 amount);
    error PrecompileFailed(address precompile);
    error UnexpectedNative(address sender);

    address internal constant HYPE_ASSET_BRIDGE = 0x2222222222222222222222222222222222222222;
    address internal constant CORE_WRITER = 0x3333333333333333333333333333333333333333;
    address internal constant SPOT_BALANCE_PRECOMPILE = 0x0000000000000000000000000000000000000801;
    address internal constant CORE_USER_EXISTS_PRECOMPILE = 0x0000000000000000000000000000000000000810;

    bytes4 internal constant SPOT_SEND_HEADER = 0x01000006;

    uint64 internal constant HYPE_CORE_INDEX = 150;

    /// @dev wHYPE holds 18 decimals, HYPE on Core holds 8.
    uint256 internal constant CORE_SCALE = 1e10;

    /// @dev Enough for a contract recipient to record the transfer, but not enough for one to burn
    ///      the compose transaction's gas. Anything needing more is paid in the wrapped token.
    uint256 internal constant NATIVE_SEND_GAS = 30_000;

    address public immutable endpoint;
    IOFT public immutable adapter;
    IWrappedNative public immutable wrappedNative;

    event DeliveredToCore(address indexed to, uint64 coreAmount);
    event DeliveredToHyperEvm(address indexed to, uint256 amount, bool native);

    constructor(IOFT _adapter) {
        endpoint = address(IOAppCore(address(_adapter)).endpoint());
        adapter = _adapter;
        wrappedNative = IWrappedNative(_adapter.token());
    }

    /// @param _message OFT compose message whose `composeMsg` is `abi.encode(address to, bool toCore)`.
    function lzCompose(
        address _oft,
        bytes32 /*_guid*/,
        bytes calldata _message,
        address /*_executor*/,
        bytes calldata /*_extraData*/
    ) external payable override {
        if (msg.sender != endpoint) revert OnlyEndpoint(msg.sender);
        if (_oft != address(adapter)) revert UnexpectedOFT(_oft);

        bytes memory composeMsg = OFTComposeMsgCodec.composeMsg(_message);
        if (composeMsg.length != 64) revert MalformedComposeMsg(composeMsg.length);
        (address to, bool toCore) = abi.decode(composeMsg, (address, bool));

        uint256 amountLD = OFTComposeMsgCodec.amountLD(_message);

        // Native dropped alongside the transfer is paid out on HyperEVM either way.
        uint256 payout = msg.value;

        if (toCore) {
            // A revert unwinds the deposit with it, leaving the wHYPE here to pay out below.
            try this.depositToCore(to, amountLD) {
                amountLD = 0;
            } catch {} // solhint-disable-line no-empty-blocks
        }

        if (amountLD > 0) {
            wrappedNative.withdraw(amountLD);
            payout += amountLD;
        }

        if (payout > 0) _payOnHyperEvm(to, payout);
    }

    /// @dev External so a Core failure can be caught and paid out on HyperEVM instead of stranding.
    function depositToCore(address _to, uint256 _amountLD) external {
        if (msg.sender != address(this)) revert OnlySelf(msg.sender);

        // sharedDecimals truncation already rounds to 1e12, so this cannot trip today. It is what
        // makes dust handling unnecessary, so fail loudly if that ever stops holding.
        if (_amountLD % CORE_SCALE != 0) revert UnscalableAmount(_amountLD);
        uint256 coreAmount = _amountLD / CORE_SCALE;

        if (!_coreUserExists(_to)) revert CoreUserNotActivated(_to);

        // Hyperliquid does not check bridge capacity itself: depositing more than the bridge holds
        // on Core locks it there permanently. Also bounds the uint64 cast, the balance being uint64.
        uint64 bridgeBalance = _bridgeSpotBalance();
        if (coreAmount > bridgeBalance) revert AssetBridgeUnderfunded(coreAmount, bridgeBalance);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 coreAmountU64 = uint64(coreAmount);

        wrappedNative.withdraw(_amountLD);

        // Credits this contract's own Core account, which the CoreWriter action then pays out.
        (bool success, ) = HYPE_ASSET_BRIDGE.call{ value: _amountLD }("");
        if (!success) revert NativeTransferFailed(_amountLD);

        bytes memory action = abi.encode(_to, HYPE_CORE_INDEX, coreAmountU64);
        ICoreWriter(CORE_WRITER).sendRawAction(abi.encodePacked(SPOT_SEND_HEADER, action));

        emit DeliveredToCore(_to, coreAmountU64);
    }

    function _payOnHyperEvm(address _to, uint256 _amount) internal {
        (bool sent, ) = _to.call{ value: _amount, gas: NATIVE_SEND_GAS }("");
        if (!sent) {
            // Recipients that cannot take native still get paid, rather than the delivery reverting.
            wrappedNative.deposit{ value: _amount }();
            IERC20(address(wrappedNative)).safeTransfer(_to, _amount);
        }

        emit DeliveredToHyperEvm(_to, _amount, sent);
    }

    function _bridgeSpotBalance() internal view returns (uint64) {
        (bool success, bytes memory result) = SPOT_BALANCE_PRECOMPILE.staticcall(
            abi.encode(HYPE_ASSET_BRIDGE, HYPE_CORE_INDEX)
        );
        if (!success) revert PrecompileFailed(SPOT_BALANCE_PRECOMPILE);
        return abi.decode(result, (SpotBalance)).total;
    }

    function _coreUserExists(address _user) internal view returns (bool) {
        (bool success, bytes memory result) = CORE_USER_EXISTS_PRECOMPILE.staticcall(abi.encode(_user));
        if (!success) revert PrecompileFailed(CORE_USER_EXISTS_PRECOMPILE);
        return abi.decode(result, (CoreUserExists)).exists;
    }

    receive() external payable {
        if (msg.sender != address(wrappedNative)) revert UnexpectedNative(msg.sender);
    }
}
