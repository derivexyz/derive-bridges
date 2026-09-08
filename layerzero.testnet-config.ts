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
    HYPE: {
        sepolia: { eid: SEPOLIA, contractName: 'HYPE' },
        hyperevm: { eid: HYPEREVM, contractName: 'HYPE_Adapter' },
    },
    KHYPE: {
        sepolia: { eid: SEPOLIA, contractName: 'KHYPE' },
        hyperevm: { eid: HYPEREVM, contractName: 'KHYPE_Adapter' },
    },
    FXRP: {
        sepolia: { eid: SEPOLIA, contractName: 'FXRP' },
        flare: { eid: FLARE, contractName: 'FXRP_Adapter' },
    },
    SOL: {
        sepolia: { eid: SEPOLIA, contractName: 'SOL' },
        solana: { eid: SOLANA, address: getOftStoreAddress(SOLANA, 'SOL') },
    },
    JITOSOL: {
        sepolia: { eid: SEPOLIA, contractName: 'JITOSOL' },
        solana: { eid: SOLANA, address: getOftStoreAddress(SOLANA, 'JITOSOL') },
    },
}

const CONFIRMATIONS: [number, number] = [15, 32]

const DVNS: [string[], []] = [['LayerZero Labs'], []]

const Connections: { [token: string]: TwoWayConfig[] } = {
    HYPE: [
        [
            Contracts.HYPE.sepolia,
            Contracts.HYPE.hyperevm,
            DVNS,
            CONFIRMATIONS,
            [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
        ],
    ],
    KHYPE: [
        [
            Contracts.KHYPE.sepolia,
            Contracts.KHYPE.hyperevm,
            DVNS,
            CONFIRMATIONS,
            [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
        ],
    ],
    FXRP: [
        [
            Contracts.FXRP.sepolia,
            Contracts.FXRP.flare,
            DVNS,
            CONFIRMATIONS,
            [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
        ],
    ],
    SOL: [
        [
            Contracts.SOL.sepolia,
            Contracts.SOL.solana,
            DVNS,
            CONFIRMATIONS,
            [SOLANA_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
        ],
    ],
    JITOSOL: [
        [
            Contracts.JITOSOL.sepolia,
            Contracts.JITOSOL.solana,
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
