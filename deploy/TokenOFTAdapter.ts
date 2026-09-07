import { type DeployFunction } from 'hardhat-deploy/types'

import {
    deployImplementation,
    deployProxy,
    deployProxyAdmin,
    saveCombinedDeployment,
} from '@layerzerolabs/devtools-evm-hardhat'

import { withBigBlock } from '../utils/hyperliquidBlocks'

const contractName = 'TokenOFTAdapter'

/// Escrows the token on its home chain: fXRP on Flare, kHYPE on HyperEVM. Which token, and under
/// what deployment name, comes from `oftAdapter` in the network config.
const deploy: DeployFunction = async (hre) => {
    const { deployer } = await hre.getNamedAccounts()

    const adapter = hre.network.config.oftAdapter
    if (adapter == null) {
        console.log(`No oftAdapter configured for ${hre.network.name}, skipping ${contractName}`)
        return
    }
    if (!adapter.tokenAddress) {
        console.warn(`oftAdapter.tokenAddress is unset for ${hre.network.name}, skipping ${contractName}`)
        return
    }

    const { address: endpointAddress } = await hre.deployments.get('EndpointV2')

    console.log(`Deploying ${adapter.deploymentName} on ${hre.network.name} with ${deployer}`)
    console.log(`Escrowing token ${adapter.tokenAddress}`)

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
                args: [adapter.tokenAddress, endpointAddress],
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

export default deploy
