// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/ILayerZeroEndpoint.sol";
import "../interfaces/ILayerZeroReceiver.sol";

/**
 * @title MockLayerZeroEndpoint
 * @dev Mock LayerZero endpoint for testing
 */
contract MockLayerZeroEndpoint is ILayerZeroEndpoint {
    uint256 public mockNativeFee = 0.001 ether;
    uint256 public mockZroFee = 0;
    
    mapping(uint16 => mapping(address => uint64)) public nonces;
    
    event MessageSent(
        uint16 indexed dstChainId,
        bytes destination,
        bytes payload,
        address refundAddress
    );
    
    function setMockFee(uint256 _nativeFee, uint256 _zroFee) external {
        mockNativeFee = _nativeFee;
        mockZroFee = _zroFee;
    }
    
    function send(
        uint16 dstChainId,
        bytes calldata destination,
        bytes calldata payload,
        address payable refundAddress,
        address /*zroPaymentAddress*/,
        bytes calldata /*adapterParams*/
    ) external payable override {
        require(msg.value >= mockNativeFee, "Insufficient fee");
        
        uint64 nonce = ++nonces[dstChainId][msg.sender];
        
        emit MessageSent(dstChainId, destination, payload, refundAddress);
        
        // Refund excess
        if (msg.value > mockNativeFee) {
            refundAddress.transfer(msg.value - mockNativeFee);
        }
    }
    
    function estimateFees(
        uint16 /*dstChainId*/,
        address /*userApplication*/,
        bytes calldata /*payload*/,
        bool /*payInZRO*/,
        bytes calldata /*adapterParams*/
    ) external view override returns (uint256 nativeFee, uint256 zroFee) {
        return (mockNativeFee, mockZroFee);
    }
    
    function receivePayload(
        uint16 srcChainId,
        bytes calldata srcAddress,
        address dstAddress,
        uint64 nonce,
        uint256 /*gasLimit*/,
        bytes calldata payload
    ) external override {
        ILayerZeroReceiver(dstAddress).lzReceive(srcChainId, srcAddress, nonce, payload);
    }
    
    function deliverMessage(
        uint16 srcChainId,
        bytes calldata srcAddress,
        address dstAddress,
        uint64 nonce,
        bytes calldata payload
    ) external {
        ILayerZeroReceiver(dstAddress).lzReceive(srcChainId, srcAddress, nonce, payload);
    }
}
