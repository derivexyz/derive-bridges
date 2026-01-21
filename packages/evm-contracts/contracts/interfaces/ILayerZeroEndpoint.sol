// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ILayerZeroEndpoint
 * @dev Mock interface for LayerZero endpoint (simplified for this implementation)
 */
interface ILayerZeroEndpoint {
    /**
     * @dev Send a cross-chain message
     */
    function send(
        uint16 dstChainId,
        bytes calldata destination,
        bytes calldata payload,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes calldata adapterParams
    ) external payable;

    /**
     * @dev Estimate fees for sending a message
     */
    function estimateFees(
        uint16 dstChainId,
        address userApplication,
        bytes calldata payload,
        bool payInZRO,
        bytes calldata adapterParams
    ) external view returns (uint256 nativeFee, uint256 zroFee);

    /**
     * @dev Receive a cross-chain message (called by LayerZero)
     */
    function receivePayload(
        uint16 srcChainId,
        bytes calldata srcAddress,
        address dstAddress,
        uint64 nonce,
        uint256 gasLimit,
        bytes calldata payload
    ) external;
}
