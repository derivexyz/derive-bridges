import { type DeployFunction } from 'hardhat-deploy/types'

import {
    deployImplementation,
    deployProxy,
    deployProxyAdmin,
    saveCombinedDeployment,
} from '@layerzerolabs/devtools-evm-hardhat'
import { EndpointId } from '@layerzerolabs/lz-definitions'

import { withBigBlock } from '../utils/hyperliquidBlocks'

const contractName = 'NativeTokenOFTAdapter'
const deploymentName = 'HYPE_Adapter'

/// Escrows native HYPE on HyperEVM. 18 decimals, matching the gas token.
const HYPE_DECIMALS = 18

const HYPEREVM_EIDS: EndpointId[] = [EndpointId.HYPERLIQUID_V2_MAINNET, EndpointId.HYPERLIQUID_V2_TESTNET]

const deploy: DeployFunction = async (hre) => {
    const { deployer } = await hre.getNamedAccounts()

    const eid = hre.network.config.eid as EndpointId
    if (!HYPEREVM_EIDS.includes(eid)) {
        console.log(`${hre.network.name} is not HyperEVM, skipping ${contractName}`)
        return
    }

    const { address: endpointAddress } = await hre.deployments.get('EndpointV2')

    console.log(`Deploying ${deploymentName} on ${hre.network.name} with ${deployer}`)

    const { address: proxyAdminAddress } = await deployProxyAdmin({
        hre,
        deployOptions: { from: deployer, args: [deployer], skipIfAlreadyDeployed: true },
        deploymentName,
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
                args: [HYPE_DECIMALS, endpointAddress],
                skipIfAlreadyDeployed: true,
                contract: contractName,
            },
            deploymentName,
        })

        await deployProxy({
            hre,
            deployOptions: {
                from: deployer,
                args: [implementationAddress, proxyAdminAddress, initializeData],
                skipIfAlreadyDeployed: true,
            },
            deploymentName,
        })
    })

    await saveCombinedDeployment({ hre, deploymentName })
}

deploy.tags = [contractName]

export default deploy
