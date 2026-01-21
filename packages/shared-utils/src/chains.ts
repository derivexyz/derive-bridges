/**
 * Chain identifiers for the OFT bridge
 */
export enum ChainId {
  // EVM Chains
  ETHEREUM = 1,
  POLYGON = 137,
  ARBITRUM = 42161,
  OPTIMISM = 10,
  BASE = 8453,
  
  // TRON
  TRON = 728126428,
  
  // Solana
  SOLANA = 1151111081099710,
  
  // LayerZero Chain IDs (for cross-chain messaging)
  LZ_ETHEREUM = 1,
  LZ_POLYGON = 109,
  LZ_ARBITRUM = 110,
  LZ_OPTIMISM = 111,
  LZ_SOLANA = 168,
}

/**
 * Chain configuration
 */
export interface ChainConfig {
  chainId: ChainId;
  name: string;
  rpcUrl: string;
  nativeCurrency: {
    name: string;
    symbol: string;
    decimals: number;
  };
  blockExplorer?: string;
}

/**
 * Get chain name by ID
 */
export function getChainName(chainId: ChainId): string {
  const names: Record<ChainId, string> = {
    [ChainId.ETHEREUM]: 'Ethereum',
    [ChainId.POLYGON]: 'Polygon',
    [ChainId.ARBITRUM]: 'Arbitrum',
    [ChainId.OPTIMISM]: 'Optimism',
    [ChainId.BASE]: 'Base',
    [ChainId.TRON]: 'TRON',
    [ChainId.SOLANA]: 'Solana',
    [ChainId.LZ_ETHEREUM]: 'Ethereum (LayerZero)',
    [ChainId.LZ_POLYGON]: 'Polygon (LayerZero)',
    [ChainId.LZ_ARBITRUM]: 'Arbitrum (LayerZero)',
    [ChainId.LZ_OPTIMISM]: 'Optimism (LayerZero)',
    [ChainId.LZ_SOLANA]: 'Solana (LayerZero)',
  };
  return names[chainId] || 'Unknown';
}

/**
 * Check if chain is EVM compatible
 */
export function isEvmChain(chainId: ChainId): boolean {
  return [
    ChainId.ETHEREUM,
    ChainId.POLYGON,
    ChainId.ARBITRUM,
    ChainId.OPTIMISM,
    ChainId.BASE,
    ChainId.TRON, // TRON is EVM-compatible
  ].includes(chainId);
}

/**
 * Check if chain is Solana
 */
export function isSolanaChain(chainId: ChainId): boolean {
  return chainId === ChainId.SOLANA || chainId === ChainId.LZ_SOLANA;
}
