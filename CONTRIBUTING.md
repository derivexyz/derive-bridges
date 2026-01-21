# Contributing to DRV Bridges

We love your input! We want to make contributing to DRV Bridges as easy and transparent as possible, whether it's:

- Reporting a bug
- Discussing the current state of the code
- Submitting a fix
- Proposing new features
- Becoming a maintainer

## Development Process

We use GitHub to host code, to track issues and feature requests, as well as accept pull requests.

1. Fork the repo and create your branch from `main`
2. If you've added code that should be tested, add tests
3. If you've changed APIs, update the documentation
4. Ensure the test suite passes
5. Make sure your code lints
6. Issue that pull request!

## Code Style

### Solidity
- Follow the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- Use 4 spaces for indentation
- Maximum line length: 120 characters
- Use NatSpec comments for all public functions

### TypeScript
- Follow the repository's ESLint configuration
- Use 2 spaces for indentation
- Maximum line length: 100 characters
- Use JSDoc comments for exported functions

### Rust (Solana)
- Follow standard Rust formatting (use `cargo fmt`)
- Use `cargo clippy` to catch common mistakes
- Document public APIs

## Testing

All code changes should include tests:

### EVM Contracts
```bash
cd packages/evm-contracts
npm test
```

### Solana Program
```bash
cd packages/solana-program
anchor test
```

### Shared Utilities
```bash
cd packages/shared-utils
npm test
```

## Pull Request Process

1. Update the README.md with details of changes if applicable
2. Update the package version following [SemVer](http://semver.org/)
3. The PR will be merged once you have the sign-off of at least one maintainer

## Security

If you discover a security vulnerability, please email security@derivexyz.com instead of using the issue tracker.

## Any contributions you make will be under the MIT Software License

In short, when you submit code changes, your submissions are understood to be under the same [MIT License](http://choosealicense.com/licenses/mit/) that covers the project.

## References

This document was adapted from the open-source contribution guidelines for [Facebook's Draft](https://github.com/facebook/draft-js/blob/master/CONTRIBUTING.md).
