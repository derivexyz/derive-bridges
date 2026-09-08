import { EndpointId } from '@layerzerolabs/lz-definitions'
import { TwoWayConfig, generateConnectionsConfig } from '@layerzerolabs/metadata-tools'
import { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import { EVM_ENFORCED_OPTIONS, SOLANA_ENFORCED_OPTIONS } from './tasks/common/constants'
import { getOftStoreAddress } from './tasks/solana'

const ETHEREUM = EndpointId.ETHEREUM_V2_MAINNET
const HYPEREVM = EndpointId.HYPERLIQUID_V2_MAINNET
const FLARE = EndpointId.FLARE_V2_MAINNET
const SOLANA = EndpointId.SOLANA_V2_MAINNET

// Ethereum is the hub: every token is minted here against an escrow on its home chain.
const Contracts: { [token: string]: { [network: string]: OmniPointHardhat } } = {
    HYPE: {
        ethereum: { eid: ETHEREUM, contractName: 'HYPE' },
        hyperevm: { eid: HYPEREVM, contractName: 'HYPE_Adapter' },
    },
    KHYPE: {
        ethereum: { eid: ETHEREUM, contractName: 'KHYPE' },
        hyperevm: { eid: HYPEREVM, contractName: 'KHYPE_Adapter' },
    },
    FXRP: {
        ethereum: { eid: ETHEREUM, contractName: 'FXRP' },
        flare: { eid: FLARE, contractName: 'FXRP_Adapter' },
    },
    SOL: {
        ethereum: { eid: ETHEREUM, contractName: 'SOL' },
        solana: { eid: SOLANA, address: getOftStoreAddress(SOLANA, 'SOL') },
    },
    JITOSOL: {
        ethereum: { eid: ETHEREUM, contractName: 'JITOSOL' },
        solana: { eid: SOLANA, address: getOftStoreAddress(SOLANA, 'JITOSOL') },
    },
}

// TODO confirmations carried over from the Derive-era config, where Derive was the source. Review
// per pathway now that Ethereum is, since its finality differs from an L2's.
const CONFIRMATIONS: [number, number] = [15, 32]

// TODO single required DVN is a 1-of-1 trust assumption. Comparable deployments run a 4-of-4 set.
const DVNS: [string[], []] = [['LayerZero Labs'], []]

const Connections: { [token: string]: TwoWayConfig[] } = {
    HYPE: [
        [
            Contracts.HYPE.ethereum,
            Contracts.HYPE.hyperevm,
            DVNS,
            CONFIRMATIONS,
            [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
        ],
    ],
    KHYPE: [
        [
            Contracts.KHYPE.ethereum,
            Contracts.KHYPE.hyperevm,
            DVNS,
            CONFIRMATIONS,
            [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
        ],
    ],
    FXRP: [
        [
            Contracts.FXRP.ethereum,
            Contracts.FXRP.flare,
            DVNS,
            CONFIRMATIONS,
            [EVM_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
        ],
    ],
    SOL: [
        [
            Contracts.SOL.ethereum,
            Contracts.SOL.solana,
            DVNS,
            CONFIRMATIONS,
            [SOLANA_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS],
        ],
    ],
    JITOSOL: [
        [
            Contracts.JITOSOL.ethereum,
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
