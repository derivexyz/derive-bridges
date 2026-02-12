import { EndpointId } from '@layerzerolabs/lz-definitions'
import { TwoWayConfig, generateConnectionsConfig } from '@layerzerolabs/metadata-tools'
import { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import { EVM_ENFORCED_OPTIONS, SOLANA_ENFORCED_OPTIONS } from './tasks/common/constants'
import { getOftStoreAddress } from './tasks/solana'

const Contracts: { [token: string]: { [network: string]: OmniPointHardhat } } = {
    JITOSOL: {
        arbSep: {
            eid: EndpointId.ARBSEP_V2_TESTNET,
            contractName: 'JITOSOL_DeriveOFTReceiver',
        },
        solana: {
            eid: EndpointId.SOLANA_V2_TESTNET,
            address: getOftStoreAddress(EndpointId.SOLANA_V2_TESTNET, 'JITOSOL'),
        },
    },
    SOL: {
        arbSep: {
            eid: EndpointId.ARBSEP_V2_TESTNET,
            contractName: 'SOL_DeriveOFTReceiver',
        },
        solana: {
            eid: EndpointId.SOLANA_V2_TESTNET,
            address: getOftStoreAddress(EndpointId.SOLANA_V2_TESTNET, 'SOL'),
        },
    },
}

const Connections: { [token: string]: TwoWayConfig[] } = {
    JITOSOL: [
        [
            Contracts.JITOSOL.arbSep,
            Contracts.JITOSOL.solana,
            [['LayerZero Labs'], []], // [ requiredDVN[], [ optionalDVN[], threshold ] ]
            [15, 32], // [dest to src confirmations, src to dest confirmations]
            [SOLANA_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS], // dest enforcedOptions, src enforcedOptions
        ],
    ],
    SOL: [
        [
            Contracts.SOL.arbSep,
            Contracts.SOL.solana,
            [['LayerZero Labs'], []], // [ requiredDVN[], [ optionalDVN[], threshold ] ]
            [15, 32], // [dest to src confirmations, src to dest confirmations]
            [SOLANA_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS], // dest enforcedOptions, src enforcedOptions
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
