// Force ts-node to use CommonJS mode
// This must be set before any imports
process.env.TS_NODE_COMPILER_OPTIONS = JSON.stringify({
    module: 'commonjs',
    esModuleInterop: true,
})

// Get the environment configuration from .env file
//
// To make use of automatic environment setup:
// - Duplicate .env.example file and name it .env
// - Fill in the environment variables
import 'dotenv/config'

import 'hardhat-deploy'
import '@nomicfoundation/hardhat-ethers'
import '@nomiclabs/hardhat-waffle'
import 'hardhat-deploy-ethers'
import 'hardhat-contract-sizer'
import '@nomiclabs/hardhat-ethers'
import '@layerzerolabs/toolbox-hardhat'

import { HardhatUserConfig, HttpNetworkAccountsUserConfig } from 'hardhat/types'

import { EndpointId } from '@layerzerolabs/lz-definitions'

import './type-extensions'
import './tasks/index'

// Set your preferred authentication method
//
// If you prefer using a mnemonic, set a MNEMONIC environment variable
// to a valid mnemonic
const MNEMONIC = process.env.MNEMONIC

// If you prefer to be authenticated using a private key, set a PRIVATE_KEY environment variable
const PRIVATE_KEY = process.env.PRIVATE_KEY

const accounts: HttpNetworkAccountsUserConfig | undefined = MNEMONIC
    ? { mnemonic: MNEMONIC }
    : PRIVATE_KEY
      ? [PRIVATE_KEY]
      : undefined

if (accounts == null) {
    console.warn(
        'Could not find MNEMONIC or PRIVATE_KEY environment variables. It will not be possible to execute transactions in your example.'
    )
}

const config: HardhatUserConfig = {
    paths: {
        cache: 'cache/hardhat',
        tests: 'test/hardhat',
    },
    solidity: {
        compilers: [
            {
                version: '0.8.22',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
        ],
    },
    networks: {
        // Hub: every token is represented on Ethereum L1.
        'ethereum-mainnet': {
            eid: EndpointId.ETHEREUM_V2_MAINNET,
            url: process.env.RPC_URL_ETHEREUM || 'https://ethereum-rpc.publicnode.com',
            accounts,
            // No `verify` block: verified on Etherscan V2 by `lz:evm:verify`, as are Base and HyperEVM.
        },
        'sepolia-testnet': {
            eid: EndpointId.SEPOLIA_V2_TESTNET,
            url: process.env.RPC_URL_SEPOLIA || 'https://sepolia.gateway.tenderly.co',
            accounts,
            verify: { etherscan: { apiUrl: 'https://eth-sepolia.blockscout.com/api' } },
        },
        // fXRP's home chain.
        'flare-mainnet': {
            eid: EndpointId.FLARE_V2_MAINNET,
            url: process.env.RPC_URL_FLARE || 'https://flare-api.flare.network/ext/C/rpc',
            accounts,
            oftAdapters: [
                {
                    tokenAddress: process.env.FXRP_FLARE_MAINNET || '0xAd552A648C74D49E10027AB8a618A3ad4901c5bE',
                    deploymentName: 'FXRP_Adapter',
                },
            ],
            verify: { etherscan: { apiUrl: 'https://flare-explorer.flare.network/api' } },
        },
        'flare-testnet': {
            eid: EndpointId.FLARE_V2_TESTNET,
            url: process.env.RPC_URL_FLARE_TESTNET || 'https://coston2-api.flare.network/ext/C/rpc',
            accounts,
            oftAdapters: [
                {
                    // FTestXRP, 6 decimals. Resolved from FlareContractRegistry ->
                    // AssetManagerFXRP.fAsset(), since Flare publishes no static address.
                    tokenAddress: process.env.FXRP_FLARE_TESTNET || '0x0b6A3645c240605887a5532109323A3E12273dc7',
                    deploymentName: 'FXRP_Adapter',
                },
            ],
            verify: { etherscan: { apiUrl: 'https://coston2-explorer.flare.network/api' } },
        },
        // cbBTC and wETH's home chain.
        'base-mainnet': {
            eid: EndpointId.BASE_V2_MAINNET,
            url: process.env.RPC_URL_BASE || 'https://mainnet.base.org',
            accounts,
            oftAdapters: [
                {
                    // Coinbase Wrapped BTC, 8 decimals, confirmed on-chain.
                    tokenAddress: process.env.CBBTC_BASE_MAINNET || '0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf',
                    deploymentName: 'CBBTC_Adapter',
                },
                {
                    // Base's canonical WETH predeploy, 18 decimals, confirmed on-chain.
                    tokenAddress: process.env.WETH_BASE_MAINNET || '0x4200000000000000000000000000000000000006',
                    deploymentName: 'WETH_Adapter',
                },
            ],
        },
        // HYPE and kHYPE's home chain. Deploys here need big blocks, handled in the deploy scripts.
        // No `verify` block: hyperevmscan.io serves only the Etherscan V2 API, which hardhat-deploy's
        // V1-style etherscan-verify cannot drive. `lz:evm:verify` can.
        'hyperevm-mainnet': {
            eid: EndpointId.HYPERLIQUID_V2_MAINNET,
            url: process.env.RPC_URL_HYPEREVM || 'https://rpc.hyperliquid.xyz/evm',
            accounts,
            // kHYPE is not bridged on mainnet yet. When it is, add an adapter here for Kinetiq Staked
            // HYPE (0xfD739d4e423301CE9385c1fb8850539D657C296D, 18 decimals, confirmed on-chain) under
            // 'KHYPE_Adapter', and KHYPE back to the mainnet hub tokens.
        },
        'hyperevm-testnet': {
            eid: EndpointId.HYPERLIQUID_V2_TESTNET,
            url: process.env.RPC_URL_HYPEREVM_TESTNET || 'https://rpc.hyperliquid-testnet.xyz/evm',
            accounts,
            oftAdapters: [
                {
                    // No kHYPE on HyperEVM testnet: left empty, the adapter escrows the stand-in.
                    tokenAddress: process.env.KHYPE_HYPEREVM_TESTNET || '',
                    deploymentName: 'KHYPE_Adapter',
                },
            ],
        },
        hardhat: {
            // Need this for testing because TestHelperOz5.sol is exceeding the compiled contract size limit
            allowUnlimitedContractSize: true,
        },
    },
    namedAccounts: {
        deployer: {
            default: 0, // wallet address of index[0], of the mnemonic in .env
        },
    },
}

export default config
