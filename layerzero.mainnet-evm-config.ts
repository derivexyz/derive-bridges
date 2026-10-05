import { EndpointId } from '@layerzerolabs/lz-definitions'
import { TwoWayConfig, generateConnectionsConfig } from '@layerzerolabs/metadata-tools'
import { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import { EVM_ENFORCED_OPTIONS, FLARE_ENFORCED_OPTIONS, NATIVE_EVM_ENFORCED_OPTIONS } from './tasks/common/constants'

const ETHEREUM = EndpointId.ETHEREUM_V2_MAINNET
const HYPEREVM = EndpointId.HYPERLIQUID_V2_MAINNET
const FLARE = EndpointId.FLARE_V2_MAINNET
const BASE = EndpointId.BASE_V2_MAINNET

// The four pathways the deployer can wire alone. SOL and jitoSOL are left to layerzero.config.ts,
// since their Solana side is admin-owned by a multisig. Wiring is idempotent, so running the full
// config later only applies what this one did not.
const Contracts: { [token: string]: { [network: string]: OmniPointHardhat } } = {
    HYPE: {
        ethereum: { eid: ETHEREUM, contractName: 'HYPE' },
        hyperevm: { eid: HYPEREVM, contractName: 'HYPE_Adapter' },
    },
    FXRP: {
        ethereum: { eid: ETHEREUM, contractName: 'FXRP' },
        flare: { eid: FLARE, contractName: 'FXRP_Adapter' },
    },
    CBBTC: {
        ethereum: { eid: ETHEREUM, contractName: 'CBBTC' },
        base: { eid: BASE, contractName: 'CBBTC_Adapter' },
    },
    WETH: {
        ethereum: { eid: ETHEREUM, contractName: 'WETH' },
        base: { eid: BASE, contractName: 'WETH_Adapter' },
    },
}

// Must match layerzero.config.ts, or the full run would undo what this one set.
const CONFIRMATIONS: [number, number] = [15, 32]

// Must match layerzero.config.ts, as above.
const DVNS: [string[], []] = [['LayerZero Labs', 'Horizen', 'Canary'], []]

const Connections: { [token: string]: TwoWayConfig[] } = {
    // Only the HyperEVM-inbound leg carries the raised floor: that is the native credit, which
    // forwards all remaining gas to the recipient. Hub-inbound is an ordinary mint.
    HYPE: [
        [
            Contracts.HYPE.ethereum,
            Contracts.HYPE.hyperevm,
            DVNS,
            CONFIRMATIONS,
            [NATIVE_EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
        ],
    ],
    FXRP: [
        [
            Contracts.FXRP.ethereum,
            Contracts.FXRP.flare,
            DVNS,
            CONFIRMATIONS,
            [FLARE_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
        ],
    ],
    CBBTC: [
        [
            Contracts.CBBTC.ethereum,
            Contracts.CBBTC.base,
            DVNS,
            CONFIRMATIONS,
            [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
        ],
    ],
    WETH: [
        [
            Contracts.WETH.ethereum,
            Contracts.WETH.base,
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
