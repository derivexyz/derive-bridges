import { type DeployFunction } from 'hardhat-deploy/types'

import {
    deployImplementation,
    deployProxy,
    deployProxyAdmin,
    saveCombinedDeployment,
} from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'

/// Ethereum L1 is the hub: every token is represented here, escrowed by an adapter on its home
/// chain. Decimals must match that home chain, which is what picks the contract.
///
/// Name and symbol mirror the token being represented, read off the live contracts. SOL and jitoSOL
/// follow the Derive representations they replace rather than Solana's own metadata, so the seed mint
/// lands in existing holders' wallets under the name they already hold. Written once by
/// `__OFT_init` - an upgrade will not change them.
export const HUB_TOKENS = [
    { deployment: 'HYPE', contract: 'TokenOFT18', name: 'HYPE', symbol: 'HYPE' },
    { deployment: 'KHYPE', contract: 'TokenOFT18', name: 'Kinetiq Staked HYPE', symbol: 'kHYPE' },
    { deployment: 'SOL', contract: 'TokenOFT9', name: 'wSOL', symbol: 'wSOL' },
    { deployment: 'JITOSOL', contract: 'TokenOFT9', name: 'jitoSOL', symbol: 'jitoSOL' },
    { deployment: 'FXRP', contract: 'TokenOFT6', name: 'FXRP', symbol: 'FXRP' },
] as const

const HUB_EIDS: EndpointId[] = [EndpointId.ETHEREUM_V2_MAINNET, EndpointId.SEPOLIA_V2_TESTNET]

const deploy: DeployFunction = async (hre) => {
    const { deployer } = await hre.getNamedAccounts()

    const eid = hre.network.config.eid as EndpointId
    if (!HUB_EIDS.includes(eid)) {
        console.log(`${hre.network.name} is not a hub chain, skipping TokenOFT deployments`)
        return
    }

    const { address: endpointAddress } = await hre.deployments.get('EndpointV2')

    const initializeInterface = new hre.ethers.utils.Interface([
        'function initialize(string memory name, string memory symbol, address delegate)',
    ])

    for (const token of HUB_TOKENS) {
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

deploy.tags = ['TokenOFT']

export default deploy
