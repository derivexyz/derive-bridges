# Security Policy

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to security@derivexyz.com.

You should receive a response within 48 hours. If for some reason you do not, please follow up via email to ensure we received your original message.

Please include the requested information listed below (as much as you can provide) to help us better understand the nature and scope of the possible issue:

- Type of issue (e.g., buffer overflow, SQL injection, cross-site scripting, etc.)
- Full paths of source file(s) related to the manifestation of the issue
- The location of the affected source code (tag/branch/commit or direct URL)
- Any special configuration required to reproduce the issue
- Step-by-step instructions to reproduce the issue
- Proof-of-concept or exploit code (if possible)
- Impact of the issue, including how an attacker might exploit the issue

## Security Best Practices

### Smart Contracts

1. **Audits**: All contracts should be professionally audited before mainnet deployment
2. **Formal Verification**: Critical functions should undergo formal verification
3. **Bug Bounty**: We maintain a bug bounty program for deployed contracts
4. **Access Control**: Use multi-signature wallets for admin functions
5. **Pausability**: Emergency pause mechanism for critical issues

### Deployment

1. **Private Keys**: Never commit private keys or mnemonics
2. **Environment Variables**: Use `.env` files (excluded from git) for sensitive data
3. **RPC Endpoints**: Use private RPC endpoints for production deployments
4. **Testnet First**: Always test on testnets before mainnet deployment

### Operations

1. **Monitoring**: Implement comprehensive monitoring and alerting
2. **Rate Limiting**: Set appropriate rate limits on bridge operations
3. **Relayer Security**: Verify all relayer messages cryptographically
4. **Incident Response**: Have a documented incident response plan

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Known Issues

Currently, there are no known security issues in released versions.

## Security Updates

Security updates will be released as patch versions and announced via:
- GitHub Security Advisories
- Project Discord/Telegram
- Email notifications to registered users

## Acknowledgments

We appreciate the security research community's efforts in responsibly disclosing vulnerabilities. Contributors who responsibly disclose valid security issues will be acknowledged (with permission) in our security hall of fame.
