# EVM/TRON Smart Contracts

This package contains the Solidity smart contracts for the OFT (Omnichain Fungible Token) bridge supporting EVM and TRON chains using **Foundry**.

## Architecture

The bridge implements a **many-to-one** architecture:

- **Source Chains** (EVM/TRON): Multiple chains where tokens are locked in adapters when bridging to the destination
- **Destination Chain** (Canonical): Single chain where tokens are minted when received from source chains

### Contracts

- **OFTSourceAdapter**: Inherits from LayerZero's `OFTAdapterUpgradeable`. Takes ERC20 tokens via approval and sends cross-chain messages to mint on destination.
- **OFTDestination**: Inherits from LayerZero's `OFTUpgradeable`. Mints tokens when receiving from source chains and tracks liquidity per chain to prevent overdrafts.

### Key Features

- **Liquidity Tracking**: Destination chain tracks how much each source chain has minted, preventing withdrawals to chains without sufficient liquidity
- **Upgradeable**: Uses OpenZeppelin's upgradeable pattern
- **Pausable**: Emergency pause mechanism
- **Supply Cap**: Optional maximum supply on destination chain

## Installation

```bash
# Install Foundry if not already installed
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install dependencies
forge install
```

## Build

```bash
forge build
```

## Test

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test testDestinationTracksSeparateLiquidityPerChain

# Run with gas reporting
forge test --gas-report
```

## Coverage

```bash
forge coverage
```

## Deployment

### Deploy Source Chain Adapter

```bash
forge script script/DeploySource.s.sol:DeploySource \
  --rpc-url $POLYGON_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

### Deploy Destination Chain

```bash
forge script script/DeployDestination.s.sol:DeployDestination \
  --rpc-url $ETHEREUM_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

## Usage

### Bridge from Source to Destination

```solidity
// 1. Approve tokens
IERC20(token).approve(address(sourceAdapter), amount);

// 2. Build send parameters
SendParam memory sendParam = SendParam({
    dstEid: DESTINATION_EID,
    to: addressToBytes32(recipient),
    amountLD: amount,
    minAmountLD: amount,
    extraOptions: options,
    composeMsg: "",
    oftCmd: ""
});

// 3. Send tokens
sourceAdapter.send{value: fee}(sendParam, MessagingFee(fee, 0), msg.sender);
```

### Check Liquidity

```solidity
// Check if chain has sufficient liquidity
bool hasLiquidity = destination.hasSufficientLiquidity(chainEid, amount);

// Get chain liquidity
uint256 liquidity = destination.getChainLiquidity(chainEid);
```

## Security Features

- **Pausable**: Contracts can be paused in emergencies
- **Access Control**: Only owner can perform administrative functions
- **Liquidity Tracking**: Prevents overdrafts by tracking per-chain liquidity
- **Supply Cap**: Optional maximum supply on destination chain
- **Upgradeable**: Can be upgraded to fix bugs or add features

## TRON Compatibility

These Solidity contracts are compatible with TRON's modified Solidity compiler:
- TRON uses addresses in different format, but the contracts handle them as bytes
- Deploy using TronBox or similar TRON-compatible tools
- The shared codebase works on both EVM and TRON

## Testing

The test suite includes:
- Deployment tests
- Liquidity tracking tests
- Multi-chain bridge support
- Security and access control
- Pause functionality
- Supply cap enforcement
- Fuzz testing for liquidity tracking

## License

MIT
