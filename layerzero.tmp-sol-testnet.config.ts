import { EndpointId } from '@layerzerolabs/lz-definitions'
import { TwoWayConfig, generateConnectionsConfig } from '@layerzerolabs/metadata-tools'
import { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import { EVM_ENFORCED_OPTIONS, SOLANA_ENFORCED_OPTIONS } from './tasks/common/constants'
import { getOftStoreAddress } from './tasks/solana'

const SEPOLIA = EndpointId.SEPOLIA_V2_TESTNET
const HYPEREVM = EndpointId.HYPERLIQUID_V2_TESTNET
const FLARE = EndpointId.FLARE_V2_TESTNET
const SOLANA = EndpointId.SOLANA_V2_TESTNET

// Sepolia stands in for the Ethereum hub.
const Contracts: { [token: string]: { [network: string]: OmniPointHardhat } } = {
    SOL: {
        sepolia: { eid: SEPOLIA, contractName: 'SOL' },
        solana: { eid: SOLANA, address: getOftStoreAddress(SOLANA, 'SOL') },
    },
}

const CONFIRMATIONS: [number, number] = [15, 32]

const DVNS: [string[], []] = [['LayerZero Labs'], []]

const Connections: { [token: string]: TwoWayConfig[] } = {
    // Only the HyperEVM-inbound leg carries the raised floor: that is the native credit, which
    // forwards all remaining gas to the recipient. Hub-inbound is an ordinary mint.
    SOL: [
        [
            Contracts.SOL.sepolia,
            Contracts.SOL.solana,
            DVNS,
            CONFIRMATIONS,
            [SOLANA_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
        ],
    ],
}

export default async function () {
    const configs: TwoWayConfig[] = []

    for (const token of Object.keys(Connections)) {
        configs.push(...Connections[token])
    }

    const contractsFlat: { contract: OmniPointHardhat }[] = Object.values(Contracts).reduce(
        (res, networkContracts) => {
            return [...res, ...Object.values(networkContracts).map((x) => ({ contract: x }))]
        },
        [] as { contract: OmniPointHardhat }[]
    )

    const connections = await generateConnectionsConfig(configs)

    return {
        contracts: contractsFlat,
        connections,
    }
}
