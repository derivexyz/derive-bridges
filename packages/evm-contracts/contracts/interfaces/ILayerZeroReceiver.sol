// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ILayerZeroReceiver
 * @dev Interface for receiving cross-chain messages
 */
interface ILayerZeroReceiver {
    /**
     * @dev Called by LayerZero endpoint to deliver a message
     * @param srcChainId Source chain identifier
     * @param srcAddress Source contract address
     * @param nonce Message nonce
     * @param payload Message payload
     */
    function lzReceive(
        uint16 srcChainId,
        bytes calldata srcAddress,
        uint64 nonce,
        bytes calldata payload
    ) external;
}
