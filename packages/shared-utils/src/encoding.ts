import { ethers } from 'ethers';

/**
 * Message types for cross-chain communication
 */
export enum MessageType {
  SEND_TOKENS = 0,
  REFUND_TOKENS = 1,
}

/**
 * Bridge message payload
 */
export interface BridgeMessage {
  messageType: MessageType;
  sourceChainId: number;
  destinationChainId: number;
  sender: string;
  recipient: string;
  amount: bigint;
  nonce: bigint;
  timestamp: number;
}

/**
 * Encode bridge message for EVM chains
 */
export function encodeEvmMessage(message: BridgeMessage): string {
  return ethers.AbiCoder.defaultAbiCoder().encode(
    ['uint8', 'uint16', 'uint16', 'address', 'bytes', 'uint256', 'uint64', 'uint256'],
    [
      message.messageType,
      message.sourceChainId,
      message.destinationChainId,
      message.sender,
      message.recipient,
      message.amount,
      message.nonce,
      message.timestamp,
    ]
  );
}

/**
 * Decode bridge message from EVM chains
 */
export function decodeEvmMessage(encodedMessage: string): BridgeMessage {
  const decoded = ethers.AbiCoder.defaultAbiCoder().decode(
    ['uint8', 'uint16', 'uint16', 'address', 'bytes', 'uint256', 'uint64', 'uint256'],
    encodedMessage
  );

  return {
    messageType: decoded[0],
    sourceChainId: decoded[1],
    destinationChainId: decoded[2],
    sender: decoded[3],
    recipient: decoded[4],
    amount: decoded[5],
    nonce: decoded[6],
    timestamp: Number(decoded[7]),
  };
}

/**
 * Encode address to bytes for cross-chain transfer
 */
export function encodeAddress(address: string, chainType: 'evm' | 'solana'): Uint8Array {
  if (chainType === 'evm') {
    // EVM addresses are 20 bytes
    return ethers.getBytes(address);
  } else {
    // TODO: Implement proper Solana address encoding using @solana/web3.js PublicKey
    throw new Error('Solana address encoding not yet implemented. Use @solana/web3.js PublicKey in production.');
  }
}

/**
 * Decode address from bytes
 */
export function decodeAddress(bytes: Uint8Array, chainType: 'evm' | 'solana'): string {
  if (chainType === 'evm') {
    // Convert bytes to hex address
    return ethers.hexlify(bytes.slice(0, 20));
  } else {
    // TODO: Implement proper Solana address decoding using @solana/web3.js PublicKey
    throw new Error('Solana address decoding not yet implemented. Use @solana/web3.js PublicKey in production.');
  }
}

/**
 * Calculate message hash for verification
 */
export function calculateMessageHash(message: BridgeMessage): string {
  const encoded = encodeEvmMessage(message);
  return ethers.keccak256(encoded);
}
