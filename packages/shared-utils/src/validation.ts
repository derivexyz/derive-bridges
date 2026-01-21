import { ethers } from 'ethers';

/**
 * Validation utilities for bridge operations
 */

/**
 * Validate Ethereum address
 */
export function isValidEvmAddress(address: string): boolean {
  try {
    return ethers.isAddress(address);
  } catch {
    return false;
  }
}

/**
 * Validate Solana address (simplified)
 * TODO: In production, use @solana/web3.js PublicKey.isOnCurve for proper validation
 * This is a basic regex-based validation and should not be used in production
 */
export function isValidSolanaAddress(address: string): boolean {
  // Basic validation: Solana addresses are base58 encoded and typically 32-44 chars
  const base58Regex = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/;
  return base58Regex.test(address);
}

/**
 * Validate amount
 */
export function isValidAmount(amount: bigint, maxAmount?: bigint): boolean {
  if (amount <= BigInt(0)) {
    return false;
  }
  if (maxAmount !== undefined && amount > maxAmount) {
    return false;
  }
  return true;
}

/**
 * Validate chain ID
 */
export function isValidChainId(chainId: number): boolean {
  return chainId > 0 && Number.isInteger(chainId);
}

/**
 * Sanitize address for cross-chain transfer
 */
export function sanitizeAddress(address: string, chainType: 'evm' | 'solana'): string {
  if (chainType === 'evm') {
    return ethers.getAddress(address); // Returns checksum address
  } else {
    // For Solana, just trim whitespace
    return address.trim();
  }
}

/**
 * Validate bridge parameters
 */
export interface BridgeParams {
  sourceChainId: number;
  destinationChainId: number;
  amount: bigint;
  recipient: string;
  fee: bigint;
}

export function validateBridgeParams(params: BridgeParams): { valid: boolean; error?: string } {
  if (!isValidChainId(params.sourceChainId)) {
    return { valid: false, error: 'Invalid source chain ID' };
  }

  if (!isValidChainId(params.destinationChainId)) {
    return { valid: false, error: 'Invalid destination chain ID' };
  }

  if (params.sourceChainId === params.destinationChainId) {
    return { valid: false, error: 'Source and destination chains must be different' };
  }

  if (!isValidAmount(params.amount)) {
    return { valid: false, error: 'Invalid amount' };
  }

  if (!params.recipient || params.recipient.length === 0) {
    return { valid: false, error: 'Invalid recipient address' };
  }

  if (params.fee < BigInt(0)) {
    return { valid: false, error: 'Invalid fee' };
  }

  return { valid: true };
}
