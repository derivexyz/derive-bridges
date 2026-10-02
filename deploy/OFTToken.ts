import { type DeployFunction } from 'hardhat-deploy/types'

import {
    deployImplementation,
    deployProxy,
    deployProxyAdmin,
    saveCombinedDeployment,
} from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'

/// Ethereum L1 is the hub: every token is represented here, escrowed by an adapter on its home
/// chain. Decimals must match that home chain, which is what picks the contract. SOL and jitoSOL
/// take the seeded one, which can mint the frozen Derive supply once.
///
/// Name and symbol mirror the token being represented, read off the live contracts. SOL and jitoSOL
/// follow the Derive representations they replace rather than Solana's own metadata, so the seed mint
/// lands in existing holders' wallets under the name they already hold. Written once by
/// `__OFT_init` - an upgrade will not change them.
const TOKENS = {
    HYPE: { deployment: 'HYPE', contract: 'OFTToken18', name: 'HYPE', symbol: 'HYPE' },
    KHYPE: { deployment: 'KHYPE', contract: 'OFTToken18', name: 'Kinetiq Staked HYPE', symbol: 'kHYPE' },
    SOL: { deployment: 'SOL', contract: 'OFTToken9Seeded', name: 'wSOL', symbol: 'wSOL' },
    JITOSOL: { deployment: 'JITOSOL', contract: 'OFTToken9Seeded', name: 'jitoSOL', symbol: 'jitoSOL' },
    FXRP: { deployment: 'FXRP', contract: 'OFTToken6', name: 'FXRP', symbol: 'FXRP' },
    CBBTC: { deployment: 'CBBTC', contract: 'OFTToken8', name: 'Coinbase Wrapped BTC', symbol: 'cbBTC' },
    WETH: { deployment: 'WETH', contract: 'OFTToken18', name: 'Wrapped Ether', symbol: 'WETH' },
} as const

export type HubToken = (typeof TOKENS)[keyof typeof TOKENS]

/// The tokens each hub carries. kHYPE is testnet only for now; cbBTC and wETH (home chain Base) are
/// mainnet only, having no testnet pathway.
export const HUB_TOKENS: Record<number, readonly HubToken[]> = {
    [EndpointId.ETHEREUM_V2_MAINNET]: [TOKENS.HYPE, TOKENS.SOL, TOKENS.JITOSOL, TOKENS.FXRP, TOKENS.CBBTC, TOKENS.WETH],
    [EndpointId.SEPOLIA_V2_TESTNET]: [TOKENS.HYPE, TOKENS.KHYPE, TOKENS.SOL, TOKENS.JITOSOL, TOKENS.FXRP],
}

const deploy: DeployFunction = async (hre) => {
    const { deployer } = await hre.getNamedAccounts()

    const eid = hre.network.config.eid as EndpointId
    const hubTokens = HUB_TOKENS[eid]
    if (hubTokens == null) {
        console.log(`${hre.network.name} is not a hub chain, skipping OFTToken deployments`)
        return
    }

    const { address: endpointAddress } = await hre.deployments.get('EndpointV2')

    const initializeInterface = new hre.ethers.utils.Interface([
        'function initialize(string memory name, string memory symbol, address delegate)',
    ])

    for (const token of hubTokens) {
        console.log(`Deploying ${token.deployment} (${token.contract}) on ${hre.network.name} with ${deployer}`)

        const { address: proxyAdminAddress } = await deployProxyAdmin({
            hre,
            deployOptions: { from: deployer, args: [deployer], skipIfAlreadyDeployed: true },
            deploymentName: token.deployment,
        })

        const { address: implementationAddress } = await deployImplementation({
            hre,
            deployOptions: {
                from: deployer,
                args: [endpointAddress],
                skipIfAlreadyDeployed: true,
                contract: token.contract,
            },
            deploymentName: token.deployment,
        })

        await deployProxy({
            hre,
            deployOptions: {
                from: deployer,
                args: [
                    implementationAddress,
                    proxyAdminAddress,
                    initializeInterface.encodeFunctionData('initialize', [token.name, token.symbol, deployer]),
                ],
                skipIfAlreadyDeployed: true,
            },
            deploymentName: token.deployment,
        })

        await saveCombinedDeployment({ hre, deploymentName: token.deployment })
    }
}

deploy.tags = ['OFTToken']

export default deploy
