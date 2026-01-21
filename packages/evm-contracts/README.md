# EVM/TRON Smart Contracts

This package contains the Solidity smart contracts for the OFT (Omnichain Fungible Token) bridge supporting EVM and TRON chains.

## Architecture

The bridge implements a **many-to-one** architecture:

- **Source Chains** (EVM/TRON): Multiple chains where tokens are burned when bridging to the destination
- **Destination Chain** (Canonical): Single chain where tokens are minted when received from source chains

### Contracts

- **OFTSource**: Deployed on source chains (EVM/TRON). Burns tokens and sends cross-chain messages.
- **OFTDestination**: Deployed on the canonical destination chain. Mints tokens when receiving from source chains.
- **MockLayerZeroEndpoint**: Mock endpoint for testing cross-chain messaging.

## Installation

```bash
npm install
```

## Compile Contracts

```bash
npm run build
```

## Run Tests

```bash
npm test
```

## Run Coverage

```bash
npm run coverage
```

## Deployment

### Deploy Source Chain Contract

1. Set environment variables in `.env`:
```
PRIVATE_KEY=your_private_key
ETHEREUM_RPC_URL=your_rpc_url
LAYERZERO_ENDPOINT=layerzero_endpoint_address
DESTINATION_CHAIN_ID=1
```

2. Deploy:
```bash
npx hardhat run scripts/deploySource.ts --network ethereum
```

### Deploy Destination Chain Contract

1. Set environment variables in `.env`:
```
PRIVATE_KEY=your_private_key
ETHEREUM_RPC_URL=your_rpc_url
LAYERZERO_ENDPOINT=layerzero_endpoint_address
```

2. Deploy:
```bash
npx hardhat run scripts/deployDestination.ts --network ethereum
```

### Configure Bridge

After deployment, you need to:

1. Set the destination address on source contracts:
```solidity
sourceOFT.setDestinationAddress(destinationOFTAddress);
```

2. Set trusted remotes on destination contract:
```solidity
destinationOFT.setTrustedRemote(sourceChainId, sourceOFTAddress);
```

## Usage

### Bridge from Source to Destination

```typescript
// Estimate fee
const fee = await sourceOFT.estimateSendFee(destinationChainId, amount);

// Send tokens
await sourceOFT.sendToChain(
  destinationChainId,
  recipientAddress,
  amount,
  { value: fee }
);
```

### Bridge from Destination to Source

```typescript
// Estimate fee
const fee = await destinationOFT.estimateSendFee(sourceChainId, amount);

// Send tokens back
await destinationOFT.sendToChain(
  sourceChainId,
  recipientAddress,
  amount,
  { value: fee }
);
```

## Security Features

- **Pausable**: Contracts can be paused in emergencies
- **Trusted Remotes**: Only authorized remote contracts can send/receive
- **Reentrancy Protection**: All state-changing functions are protected
- **Supply Cap**: Optional maximum supply on destination chain
- **Owner Controls**: Critical functions restricted to contract owner

## TRON Compatibility

These Solidity contracts are compatible with TRON's modified Solidity compiler. Key considerations:

- TRON uses addresses in base58 format, but the contracts handle them as bytes
- Gas mechanics differ slightly, but the core logic remains the same
- Deploy using TronBox or similar TRON-compatible tools

## Testing

The test suite includes:
- Deployment tests
- Bridge functionality (source to destination)
- Reverse bridge (destination to source)
- Multi-source bridge support
- Security and access control
- Fee estimation
- Error handling

Run tests with:
```bash
npm test
```

## License

MIT
