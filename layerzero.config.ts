import { EndpointId } from '@layerzerolabs/lz-definitions'
import { generateConnectionsConfig } from '@layerzerolabs/metadata-tools'
import { OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

import { EVM_ENFORCED_OPTIONS, SOLANA_ENFORCED_OPTIONS } from './tasks/common/constants'
import { getOftStoreAddress } from './tasks/solana'

const arbitrumContract: OmniPointHardhat = {
    eid: EndpointId.ARBSEP_V2_TESTNET,
    contractName: 'DeriveOFTReceiver',
}

const solanaContract: OmniPointHardhat = {
    eid: EndpointId.SOLANA_V2_TESTNET,
    address: getOftStoreAddress(EndpointId.SOLANA_V2_TESTNET, 'JITOSOL'),
}


// Learn about Message Execution Options: https://docs.layerzero.network/v2/developers/solana/oft/overview#message-execution-options
// Learn more about the Simple Config Generator - https://docs.layerzero.network/v2/developers/evm/technical-reference/simple-config
export default async function () {
    // note: pathways declared here are automatically bidirectional
    // if you declare A,B there's no need to declare B,A
    const connections = await generateConnectionsConfig([
        [
            arbitrumContract, // Chain A contract
            solanaContract, // Chain B contract
            [['LayerZero Labs'], []], // [ requiredDVN[], [ optionalDVN[], threshold ] ]
            [15, 32], // [A to B confirmations, B to A confirmations]
            [SOLANA_ENFORCED_OPTIONS, EVM_ENFORCED_OPTIONS], // Chain B enforcedOptions, Chain A enforcedOptions
        ],
    ])

    return {
        contracts: [{ contract: arbitrumContract }, { contract: solanaContract }],
        connections,
    }
}
