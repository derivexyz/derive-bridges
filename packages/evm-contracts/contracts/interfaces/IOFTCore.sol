// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IOFTCore
 * @dev Core interface for Omnichain Fungible Token functionality
 */
interface IOFTCore {
    /**
     * @dev Emitted when tokens are sent to another chain
     */
    event SendToChain(
        uint16 indexed dstChainId,
        address indexed from,
        bytes indexed toAddress,
        uint256 amount,
        uint64 nonce
    );

    /**
     * @dev Emitted when tokens are received from another chain
     */
    event ReceiveFromChain(
        uint16 indexed srcChainId,
        bytes indexed fromAddress,
        address indexed toAddress,
        uint256 amount,
        uint64 nonce
    );

    /**
     * @dev Send tokens to another chain
     * @param dstChainId Destination chain ID
     * @param toAddress Recipient address on destination chain
     * @param amount Amount of tokens to send
     */
    function sendToChain(
        uint16 dstChainId,
        bytes calldata toAddress,
        uint256 amount
    ) external payable returns (uint64 nonce);

    /**
     * @dev Estimate fee for sending tokens to another chain
     * @param dstChainId Destination chain ID
     * @param amount Amount of tokens to send
     */
    function estimateSendFee(
        uint16 dstChainId,
        uint256 amount
    ) external view returns (uint256 nativeFee);
}
