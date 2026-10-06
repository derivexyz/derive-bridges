import assert from 'assert'

import { type DeployFunction } from 'hardhat-deploy/types'

import { EndpointId } from '@layerzerolabs/lz-definitions'

const contractName = 'StandInToken'

/// LayerZero V2 testnet endpoint ids are 40xxx; mainnet ids are 30xxx.
const LOWEST_TESTNET_EID = 40_000

export interface StandIn {
    deployment: string
    name: string
    symbol: string
    decimals: number
}

/// Home-chain tokens with no testnet deployment, keyed by the chain that needs one. fXRP is absent
/// because Coston2 has a real FTestXRP with a faucet.
export const STAND_INS: Record<number, StandIn> = {
    [EndpointId.HYPERLIQUID_V2_TESTNET]: {
        deployment: 'KHYPE_StandIn',
        name: 'Kinetiq Staked HYPE (testnet stand-in)',
        symbol: 'kHYPE',
        decimals: 18,
    },
}

const deploy: DeployFunction = async (hre) => {
    const { deployer } = await hre.getNamedAccounts()

    const eid = hre.network.config.eid as EndpointId
    const standIn = STAND_INS[eid]
    if (standIn == null) {
        console.log(`No stand-in token needed on ${hre.network.name}`)
        return
    }

    // This token mints to anyone. Refuse outright rather than relying on the table staying testnet-only.
    assert(eid >= LOWEST_TESTNET_EID, `${contractName} must never be deployed to a mainnet endpoint (${eid})`)

    const { address } = await hre.deployments.deploy(standIn.deployment, {
        from: deployer,
        contract: contractName,
        args: [standIn.name, standIn.symbol, standIn.decimals],
        log: true,
        skipIfAlreadyDeployed: true,
    })

    console.log(`${standIn.deployment} (${standIn.symbol}, ${standIn.decimals} decimals) at ${address}`)
}

deploy.tags = [contractName]

export default deploy
