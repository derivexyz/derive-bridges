/**
 * Fee estimation for cross-chain transfers
 */
export interface FeeEstimate {
  nativeFee: bigint;
  zroFee: bigint;
  totalFee: bigint;
}

/**
 * Estimate fees for cross-chain transfer
 * This is a simplified version - in production, would query actual LayerZero endpoints
 */
export function estimateBridgeFee(
  sourceChainId: number,
  destinationChainId: number,
  amount: bigint,
  payloadSize: number
): FeeEstimate {
  // Base fee calculation (simplified)
  const baseFee = BigInt(1e15); // 0.001 ETH base
  const sizeFee = BigInt(payloadSize) * BigInt(1e12); // Per-byte fee
  const amountFee = amount / BigInt(10000); // 0.01% of amount

  const nativeFee = baseFee + sizeFee + amountFee;
  const zroFee = BigInt(0); // Not using ZRO token for fees

  return {
    nativeFee,
    zroFee,
    totalFee: nativeFee + zroFee,
  };
}

/**
 * Format fee for display
 */
export function formatFee(fee: bigint, decimals: number = 18): string {
  const divisor = BigInt(10 ** decimals);
  const whole = fee / divisor;
  const fraction = fee % divisor;
  
  const fractionStr = fraction.toString().padStart(decimals, '0').slice(0, 6);
  return `${whole}.${fractionStr}`;
}

/**
 * Validate fee is sufficient
 */
export function validateFee(providedFee: bigint, requiredFee: bigint): boolean {
  return providedFee >= requiredFee;
}
