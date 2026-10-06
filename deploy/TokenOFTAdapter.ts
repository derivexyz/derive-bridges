import { type HardhatRuntimeEnvironment } from 'hardhat/types'
import { type DeployFunction } from 'hardhat-deploy/types'

import {
    deployImplementation,
    deployProxy,
    deployProxyAdmin,
    saveCombinedDeployment,
} from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'

import { type OftAdapterConfig } from '../type-extensions'
import { withBigBlock } from '../utils/hyperliquidBlocks'

import { STAND_INS } from './StandInToken'

const contractName = 'TokenOFTAdapter'

/// Escrows the token on its home chain: fXRP on Flare, kHYPE on HyperEVM, cbBTC and wETH on Base.
/// Which tokens, and under what deployment names, come from `oftAdapters` in the network config. Where a chain has no real
/// token to escrow, the stand-in deployed alongside stands in for it.
const deploy: DeployFunction = async (hre) => {
    const adapters = hre.network.config.oftAdapters ?? []
    if (adapters.length === 0) {
        console.log(`No oftAdapters configured for ${hre.network.name}, skipping ${contractName}`)
        return
    }

    for (const adapter of adapters) {
        await deployAdapter(hre, adapter)
    }
}

async function deployAdapter(hre: HardhatRuntimeEnvironment, adapter: OftAdapterConfig) {
    const { deployer } = await hre.getNamedAccounts()

    const eid = hre.network.config.eid as EndpointId
    const standIn = STAND_INS[eid]
    const tokenAddress =
        adapter.tokenAddress || (standIn && (await hre.deployments.getOrNull(standIn.deployment))?.address)

    if (!tokenAddress) {
        console.warn(
            `No token for ${adapter.deploymentName} on ${hre.network.name}: set its tokenAddress, or add a stand-in. Skipping.`
        )
        return
    }

    const { address: endpointAddress } = await hre.deployments.get('EndpointV2')

    console.log(`Deploying ${adapter.deploymentName} on ${hre.network.name} with ${deployer}`)
    console.log(`Escrowing token ${tokenAddress}${adapter.tokenAddress ? '' : ' (stand-in)'}`)

    const { address: proxyAdminAddress } = await deployProxyAdmin({
        hre,
        deployOptions: { from: deployer, args: [deployer], skipIfAlreadyDeployed: true },
        deploymentName: adapter.deploymentName,
    })

    const initializeData = new hre.ethers.utils.Interface(['function initialize(address delegate)']).encodeFunctionData(
        'initialize',
        [deployer]
    )

    await withBigBlock(hre, async () => {
        const { address: implementationAddress } = await deployImplementation({
            hre,
            deployOptions: {
                from: deployer,
                args: [tokenAddress, endpointAddress],
                skipIfAlreadyDeployed: true,
                contract: contractName,
            },
            deploymentName: adapter.deploymentName,
        })

        await deployProxy({
            hre,
            deployOptions: {
                from: deployer,
                args: [implementationAddress, proxyAdminAddress, initializeData],
                skipIfAlreadyDeployed: true,
            },
            deploymentName: adapter.deploymentName,
        })
    })

    await saveCombinedDeployment({ hre, deploymentName: adapter.deploymentName })
}

deploy.tags = [contractName]
// The stand-in has to exist before this can escrow it.
deploy.dependencies = ['StandInToken']

export default deploy
