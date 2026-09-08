import { EndpointId } from '@layerzerolabs/lz-definitions'
import { TwoWayConfig, generateConnectionsConfig } from '@layerzerolabs/metadata-tools'
import { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import { EVM_ENFORCED_OPTIONS, NATIVE_EVM_ENFORCED_OPTIONS } from './tasks/common/constants'

const SEPOLIA = EndpointId.SEPOLIA_V2_TESTNET
const HYPEREVM = EndpointId.HYPERLIQUID_V2_TESTNET
const FLARE = EndpointId.FLARE_V2_TESTNET

// The three pathways that need no Solana keypair, no init-config and no wrapped SOL. Wire this to
// prove the mesh, then move to layerzero.testnet-config.ts to add SOL and jitoSOL. Wiring is
// idempotent, so the second run only applies what this one did not.
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
}

const CONFIRMATIONS: [number, number] = [15, 32]

const DVNS: [string[], []] = [['LayerZero Labs'], []]

const Connections: { [token: string]: TwoWayConfig[] } = {
    // Only the HyperEVM-inbound leg carries the raised floor: that is the native credit, which
    // forwards all remaining gas to the recipient. Hub-inbound is an ordinary mint.
    HYPE: [
        [
            Contracts.HYPE.sepolia,
            Contracts.HYPE.hyperevm,
            DVNS,
            CONFIRMATIONS,
            [NATIVE_EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
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
