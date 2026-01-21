# Solana OFT Bridge Program

This package contains the Solana program for the OFT (Omnichain Fungible Token) bridge.

## Architecture

The Solana program implements the source chain logic for the many-to-one bridge:

- **Send to Destination**: Burns SPL tokens and emits events for relayers
- **Receive from Destination**: Mints SPL tokens when receiving from the canonical chain

## Prerequisites

- Rust 1.70+
- Solana CLI 1.17+
- Anchor Framework 0.29+
- Node.js 18+

## Installation

```bash
npm install
```

## Build

```bash
anchor build
```

or

```bash
npm run build
```

## Test

```bash
anchor test
```

or

```bash
npm test
```

## Program Structure

### Instructions

1. **initialize**: Initialize the bridge configuration
   - Sets destination chain ID
   - Creates bridge authority PDA
   - Sets initial configuration

2. **send_to_chain**: Send tokens from Solana to destination chain
   - Burns tokens from sender
   - Emits event for off-chain relayer
   - Increments nonce

3. **receive_from_chain**: Receive tokens from another chain
   - Validates relayer (in production, would verify signatures/proofs)
   - Mints tokens to recipient
   - Emits event

4. **set_paused**: Emergency pause mechanism
   - Only callable by authority
   - Pauses all bridging operations

### Accounts

- **BridgeConfig**: Stores bridge configuration and state
  - Authority
  - Destination chain ID
  - Pause status
  - Nonce counter

### Events

- **SendToChainEvent**: Emitted when tokens are sent
- **ReceiveFromChainEvent**: Emitted when tokens are received
- **PausedEvent**: Emitted when pause status changes

## Deployment

### 1. Build the program

```bash
anchor build
```

### 2. Get program ID

```bash
solana address -k target/deploy/oft_bridge-keypair.json
```

### 3. Update program ID

Update the program ID in:
- `Anchor.toml`
- `programs/oft-bridge/src/lib.rs` (declare_id!)

### 4. Deploy

```bash
anchor deploy
```

### 5. Initialize

```typescript
await program.methods
  .initialize(destinationChainId, authorityBump)
  .accounts({
    bridgeConfig,
    authority: wallet.publicKey,
    bridgeAuthority,
    systemProgram: SystemProgram.programId,
  })
  .rpc();
```

## Usage

### Send Tokens to Destination Chain

```typescript
await program.methods
  .sendToChain(destinationChainId, toAddress, amount)
  .accounts({
    bridgeConfig,
    tokenMint,
    userTokenAccount,
    user: wallet.publicKey,
    tokenProgram: TOKEN_PROGRAM_ID,
  })
  .rpc();
```

### Receive Tokens (Relayer)

```typescript
await program.methods
  .receiveFromChain(sourceChainId, fromAddress, amount, nonce)
  .accounts({
    bridgeConfig,
    tokenMint,
    recipientTokenAccount,
    recipient,
    bridgeAuthority,
    relayer: relayer.publicKey,
    tokenProgram: TOKEN_PROGRAM_ID,
  })
  .signers([relayer])
  .rpc();
```

## Security Considerations

1. **Relayer Authorization**: In production, implement signature verification for relayers
2. **Nonce Tracking**: Implement proper nonce tracking to prevent replay attacks
3. **Rate Limiting**: Consider implementing rate limits for bridging operations
4. **Multi-sig Authority**: Use a multi-sig wallet for the bridge authority
5. **Audit**: Get the program audited before mainnet deployment

## Testing

The test suite includes:
- Program initialization
- Token sending (burn)
- Token receiving (mint)
- Pause functionality
- Error handling

Run tests:
```bash
anchor test
```

## License

MIT
