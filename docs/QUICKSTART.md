# Quick Start Guide

This guide will help you get started with the DRV Bridges OFT (Omnichain Fungible Token) bridge.

## Overview

DRV Bridges is a production-grade monorepo implementing a LayerZero-style OFT bridge with a many-to-one architecture:

- **Source Chains**: EVM (Ethereum, Polygon, Arbitrum, etc.), TRON, and Solana
- **Destination Chain**: Single canonical chain where all tokens are aggregated
- **Architecture**: Burn-mint model for token bridging

## Prerequisites

### For EVM/TRON Development
- Node.js 18+ and npm 9+
- A wallet with testnet funds
- RPC endpoints for target chains

### For Solana Development
- Rust 1.70+
- Solana CLI 1.17+
- Anchor Framework 0.29+
- SOL for deployment (devnet/testnet)

## Installation

```bash
# Clone the repository
git clone https://github.com/derivexyz/drv-bridges.git
cd drv-bridges

# Install dependencies for all packages
npm install

# Build all packages
npm run build
```

## Running Tests

```bash
# Test all packages
npm test

# Test EVM contracts
cd packages/evm-contracts && npm test

# Test Solana program
cd packages/solana-program && anchor test
```

## Security

Before mainnet deployment:
1. Get professional security audit
2. Test thoroughly on testnets
3. Use multi-signature wallets for admin functions
4. Set up monitoring and alerting
5. Implement rate limiting

## Support

- GitHub Issues: [Report bugs](https://github.com/derivexyz/drv-bridges/issues)
- Documentation: [Full docs](../README.md)

## License

MIT License - see [LICENSE](../LICENSE) for details.
