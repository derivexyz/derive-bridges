# Shared Utilities

Shared TypeScript utilities for the OFT bridge, providing common functionality across EVM, TRON, and Solana chains.

## Features

- **Chain Management**: Chain IDs, configurations, and chain type detection
- **Message Encoding/Decoding**: Cross-chain message serialization
- **Fee Estimation**: Bridge fee calculation utilities
- **Validation**: Address and parameter validation

## Installation

```bash
npm install
```

## Build

```bash
npm run build
```

## Usage

### Chain Utilities

```typescript
import { ChainId, getChainName, isEvmChain, isSolanaChain } from '@drv-bridges/shared-utils';

// Get chain name
const name = getChainName(ChainId.ETHEREUM); // "Ethereum"

// Check chain type
const isEvm = isEvmChain(ChainId.TRON); // true (TRON is EVM-compatible)
const isSol = isSolanaChain(ChainId.SOLANA); // true
```

### Message Encoding

```typescript
import { encodeEvmMessage, decodeEvmMessage, MessageType } from '@drv-bridges/shared-utils';

const message = {
  messageType: MessageType.SEND_TOKENS,
  sourceChainId: 101,
  destinationChainId: 1,
  sender: '0x...',
  recipient: '0x...',
  amount: BigInt(1000),
  nonce: BigInt(1),
  timestamp: Date.now(),
};

// Encode for cross-chain transfer
const encoded = encodeEvmMessage(message);

// Decode received message
const decoded = decodeEvmMessage(encoded);
```

### Fee Estimation

```typescript
import { estimateBridgeFee, formatFee } from '@drv-bridges/shared-utils';

const feeEstimate = estimateBridgeFee(
  101, // source chain
  1,   // destination chain
  BigInt(1000), // amount
  256  // payload size
);

console.log(`Fee: ${formatFee(feeEstimate.totalFee)} ETH`);
```

### Validation

```typescript
import { isValidEvmAddress, validateBridgeParams } from '@drv-bridges/shared-utils';

// Validate address
const isValid = isValidEvmAddress('0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb');

// Validate bridge parameters
const validation = validateBridgeParams({
  sourceChainId: 101,
  destinationChainId: 1,
  amount: BigInt(1000),
  recipient: '0x...',
  fee: BigInt(1e15),
});

if (!validation.valid) {
  console.error(validation.error);
}
```

## License

MIT
