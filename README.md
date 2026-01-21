# DRV Bridges

Production-grade monorepo for a LayerZero-style OFT (Omnichain Fungible Token) bridge supporting EVM, TRON, and Solana chains.

## Architecture

The bridge implements a **many-to-one** architecture:

- **Source Chains**: Multiple chains (EVM, TRON, Solana) where tokens are burned when bridging
- **Destination Chain**: Single canonical chain where tokens are minted when received

```
┌─────────────┐
│  Ethereum   │──┐
└─────────────┘  │
                 │
┌─────────────┐  │     ┌──────────────┐
│   Polygon   │──┼────▶│ Destination  │
└─────────────┘  │     │ (Canonical)  │
                 │     └──────────────┘
┌─────────────┐  │
│   Solana    │──┘
└─────────────┘
```

## Packages

### 📦 [@drv-bridges/evm-contracts](./packages/evm-contracts)

Solidity smart contracts for EVM and TRON chains. Includes:
- **OFTSource**: Source chain contract (burns tokens)
- **OFTDestination**: Destination chain contract (mints tokens)
- Comprehensive test suite with Hardhat

**Key Features:**
- EVM and TRON compatible (shared Solidity codebase)
- LayerZero integration for cross-chain messaging
- Pausable, upgradeable, and owner-controlled
- Gas-optimized with OpenZeppelin libraries

### 📦 [@drv-bridges/solana-program](./packages/solana-program)

Anchor-based Solana program for bridging. Includes:
- Token burn/mint functionality
- Cross-chain message handling
- PDA-based authority management

**Key Features:**
- Built with Anchor framework
- SPL Token integration
- Event-driven architecture for relayers

### 📦 [@drv-bridges/shared-utils](./packages/shared-utils)

TypeScript utilities shared across all chains:
- Chain configuration and management
- Message encoding/decoding
- Fee estimation
- Address validation

## Getting Started

### Prerequisites

- Node.js 18+
- npm 9+
- Rust 1.70+ (for Solana)
- Solana CLI 1.17+ (for Solana)
- Anchor 0.29+ (for Solana)

### Installation

```bash
# Install all dependencies
npm install

# Build all packages
npm run build
```

### Development

```bash
# Run tests for all packages
npm test

# Run linting
npm run lint

# Clean build artifacts
npm run clean
```

## Deployment

### 1. Deploy EVM/TRON Contracts

#### Source Chain (e.g., Polygon)

```bash
cd packages/evm-contracts

# Set environment variables
export PRIVATE_KEY=your_private_key
export POLYGON_RPC_URL=your_rpc_url
export LAYERZERO_ENDPOINT=layerzero_endpoint_address
export DESTINATION_CHAIN_ID=1

# Deploy
npx hardhat run scripts/deploySource.ts --network polygon
```

#### Destination Chain (e.g., Ethereum)

```bash
cd packages/evm-contracts

# Set environment variables
export PRIVATE_KEY=your_private_key
export ETHEREUM_RPC_URL=your_rpc_url
export LAYERZERO_ENDPOINT=layerzero_endpoint_address

# Deploy
npx hardhat run scripts/deployDestination.ts --network ethereum
```

### 2. Deploy Solana Program

```bash
cd packages/solana-program

# Build
anchor build

# Deploy
anchor deploy

# Initialize
anchor run initialize
```

### 3. Configure Bridge

After deployment, configure trusted remotes:

```bash
# On source contracts
sourceOFT.setDestinationAddress(destinationOFTAddress)

# On destination contract
destinationOFT.setTrustedRemote(sourceChainId, sourceOFTAddress)
```

## Usage Example

### Bridge from EVM to Destination

```typescript
import { ethers } from 'ethers';

// Estimate fee
const fee = await sourceOFT.estimateSendFee(destinationChainId, amount);

// Send tokens
const tx = await sourceOFT.sendToChain(
  destinationChainId,
  recipientAddressBytes,
  amount,
  { value: fee }
);

await tx.wait();
```

### Bridge from Solana to Destination

```typescript
import { AnchorProvider } from '@coral-xyz/anchor';

// Send tokens
await program.methods
  .sendToChain(destinationChainId, recipientAddress, amount)
  .accounts({
    bridgeConfig,
    tokenMint,
    userTokenAccount,
    user: wallet.publicKey,
    tokenProgram: TOKEN_PROGRAM_ID,
  })
  .rpc();
```

## Security

### Security Features

- **Pausable**: Emergency stop mechanism
- **Trusted Remotes**: Only authorized contracts can communicate
- **Reentrancy Protection**: Guards on all state-changing functions
- **Supply Cap**: Optional maximum supply on destination chain
- **Access Control**: Owner-only administrative functions

### Security Considerations

1. **Audits**: Get contracts professionally audited before mainnet deployment
2. **Relayer Security**: Implement signature verification for relayers on Solana
3. **Rate Limiting**: Consider implementing bridge rate limits
4. **Monitoring**: Set up monitoring and alerts for bridge operations
5. **Multi-sig**: Use multi-signature wallets for owner accounts

## Testing

Each package includes comprehensive tests:

```bash
# Test EVM contracts
cd packages/evm-contracts && npm test

# Test Solana program
cd packages/solana-program && anchor test

# Test shared utilities
cd packages/shared-utils && npm test
```

## Contributing

We welcome contributions! Please follow these guidelines:

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Ensure all tests pass
5. Submit a pull request

## Architecture Details

### Message Flow

1. **User initiates bridge**: Calls `sendToChain` on source chain contract
2. **Tokens burned**: Source contract burns user's tokens
3. **Message sent**: LayerZero endpoint transmits message
4. **Relayer picks up**: Off-chain relayer detects event
5. **Destination receives**: Destination contract receives message via `lzReceive`
6. **Tokens minted**: Destination contract mints tokens to recipient

### Cross-Chain Communication

The bridge uses LayerZero's messaging protocol for cross-chain communication:
- **EVM/TRON**: Direct LayerZero integration
- **Solana**: Event-based relayer system (compatible with LayerZero's approach)

### Token Economics

- **Source Chains**: Tokens are burned on send, minted on receive
- **Destination Chain**: Tokens are minted on receive, burned on send back
- **Total Supply**: Constant across all chains (burn-mint model)

## Roadmap

- [ ] Additional chain support (Cosmos, Near, etc.)
- [ ] Governance token for bridge protocol
- [ ] Fee sharing mechanism
- [ ] Bridge analytics dashboard
- [ ] Automated relayer infrastructure
- [ ] Insurance fund for bridge security

## License

MIT

## Support

For questions and support:
- GitHub Issues: [github.com/derivexyz/drv-bridges/issues](https://github.com/derivexyz/drv-bridges/issues)
- Documentation: [docs.derivexyz.com](https://docs.derivexyz.com)

---

Built with ❤️ by Derive XYZ