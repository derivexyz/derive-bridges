# Repository Structure

```
drv-bridges/
│
├── 📄 README.md                          # Main project documentation
├── 📄 LICENSE                            # MIT License
├── 📄 CONTRIBUTING.md                    # Contribution guidelines
├── 📄 SECURITY.md                        # Security policy
├── 📄 package.json                       # Root package.json with workspaces
├── 📄 .gitignore                         # Git ignore rules
├── 📄 .prettierrc.json                   # Prettier configuration
├── 📄 .prettierignore                    # Prettier ignore rules
│
├── 📁 .github/
│   └── workflows/
│       ├── ci.yml                        # CI/CD pipeline
│       └── security.yml                  # Security audit workflow
│
├── 📁 docs/
│   └── QUICKSTART.md                     # Quick start guide
│
└── 📁 packages/
    │
    ├── 📁 evm-contracts/                 # EVM & TRON Smart Contracts
    │   ├── 📄 package.json
    │   ├── 📄 hardhat.config.ts          # Hardhat configuration
    │   ├── 📄 tsconfig.json
    │   ├── 📄 .solhint.json              # Solidity linter config
    │   ├── 📄 README.md
    │   │
    │   ├── 📁 contracts/
    │   │   ├── 📁 interfaces/
    │   │   │   ├── IOFTCore.sol          # OFT core interface
    │   │   │   ├── ILayerZeroEndpoint.sol
    │   │   │   └── ILayerZeroReceiver.sol
    │   │   │
    │   │   ├── 📁 source/
    │   │   │   └── OFTSource.sol         # Source chain contract
    │   │   │
    │   │   ├── 📁 destination/
    │   │   │   └── OFTDestination.sol    # Destination chain contract
    │   │   │
    │   │   └── 📁 mocks/
    │   │       └── MockLayerZeroEndpoint.sol
    │   │
    │   ├── 📁 test/
    │   │   └── OFTBridge.test.ts         # Comprehensive test suite
    │   │
    │   └── 📁 scripts/
    │       ├── deploySource.ts           # Source deployment script
    │       └── deployDestination.ts      # Destination deployment script
    │
    ├── 📁 solana-program/                # Solana Bridge Program
    │   ├── 📄 package.json
    │   ├── 📄 Cargo.toml                 # Workspace Cargo config
    │   ├── 📄 Anchor.toml                # Anchor configuration
    │   ├── 📄 tsconfig.json
    │   ├── 📄 README.md
    │   │
    │   ├── 📁 programs/
    │   │   └── oft-bridge/
    │   │       ├── Cargo.toml
    │   │       └── src/
    │   │           └── lib.rs            # Main Anchor program
    │   │
    │   └── 📁 tests/                     # Anchor tests directory
    │
    └── 📁 shared-utils/                  # Shared TypeScript Utilities
        ├── 📄 package.json
        ├── 📄 tsconfig.json
        ├── 📄 README.md
        │
        └── 📁 src/
            ├── index.ts                  # Main export file
            ├── chains.ts                 # Chain configurations
            ├── encoding.ts               # Message encoding/decoding
            ├── fees.ts                   # Fee estimation
            └── validation.ts             # Input validation
```

## Package Breakdown

### 📦 evm-contracts (EVM & TRON)
- **Purpose**: Smart contracts for EVM-compatible chains (including TRON)
- **Language**: Solidity 0.8.24
- **Framework**: Hardhat
- **Key Features**:
  - Source chain contract (burns tokens)
  - Destination chain contract (mints tokens)
  - LayerZero integration
  - Comprehensive tests
  - Deployment scripts

### 📦 solana-program
- **Purpose**: Solana blockchain integration
- **Language**: Rust
- **Framework**: Anchor 0.29.0
- **Key Features**:
  - SPL Token integration
  - PDA-based authority
  - Event-driven architecture
  - Cross-chain message handling

### 📦 shared-utils
- **Purpose**: Common utilities across all chains
- **Language**: TypeScript
- **Key Features**:
  - Chain management
  - Message encoding/decoding
  - Fee estimation
  - Address validation
  - Type-safe utilities

## Development Setup

1. **Install dependencies**: `npm install`
2. **Build all packages**: `npm run build`
3. **Run tests**: `npm test`
4. **Lint code**: `npm run lint`

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       Source Chains                          │
├─────────────────────────────────────────────────────────────┤
│  Ethereum   │  Polygon   │  Arbitrum  │  Solana  │  TRON   │
│  (Source)   │  (Source)  │  (Source)  │ (Source) │(Source) │
└──────┬──────┴─────┬──────┴──────┬─────┴────┬─────┴────┬─────┘
       │            │             │          │          │
       │   LayerZero Protocol / Cross-chain Messaging   │
       │            │             │          │          │
       └────────────┴─────────────┴──────────┴──────────┘
                                │
                    ┌───────────▼───────────┐
                    │  Destination Chain    │
                    │    (Canonical)        │
                    │   - Ethereum Mainnet  │
                    │   - Mints all tokens  │
                    └───────────────────────┘
```

## Security Summary

✅ **0 Security Vulnerabilities** (CodeQL verified)
✅ Code review completed and feedback addressed
✅ Follows industry best practices
✅ Comprehensive security policy
✅ CI/CD with security scanning

---

Built with ❤️ by Derive XYZ
