/// <reference types="jest" />

// The Solana task barrel reaches an ESM-only dependency that jest cannot transform, and these tests
// only care about the shape of the config. Real store addresses are covered by the fork tests.
jest.mock('../../tasks/solana', () => ({
    getOftStoreAddress: (eid: number, token: string) => `oft-store-${token}-${eid}`,
}))

import { EndpointId } from '@layerzerolabs/lz-definitions'

import { deploymentName as nativeAdapterDeployment } from '../../deploy/NativeTokenOFTAdapter'
import { HUB_TOKENS } from '../../deploy/OFTToken'
import mainnetConfig from '../../layerzero.config'
import mainnetEvmConfig from '../../layerzero.mainnet-evm-config'
import testnetConfig from '../../layerzero.testnet-config'
import evmConfig from '../../layerzero.testnet-evm-config'

// Adapter names come from `oftAdapter.deploymentName` in hardhat.config.ts. Duplicated here rather than
// importing the hardhat config, which would pull the whole plugin chain into jest.
const ADAPTER_DEPLOYMENTS = ['FXRP_Adapter', 'KHYPE_Adapter', 'CBBTC_Adapter', 'WETH_Adapter', nativeAdapterDeployment]

type OmniPoint = { eid: number; contractName?: string; address?: string }
type LzConfig = { contracts: { contract: OmniPoint }[]; connections: unknown[] }

const SUITES = [
    {
        label: 'mainnet',
        build: mainnetConfig as unknown as () => Promise<LzConfig>,
        hubEid: EndpointId.ETHEREUM_V2_MAINNET as number,
        solanaEid: EndpointId.SOLANA_V2_MAINNET as number,
        tokens: 6,
    },
    {
        label: 'testnet',
        build: testnetConfig as unknown as () => Promise<LzConfig>,
        hubEid: EndpointId.SEPOLIA_V2_TESTNET as number,
        solanaEid: EndpointId.SOLANA_V2_TESTNET as number,
        tokens: 5,
    },
]

for (const { label, build, hubEid, solanaEid, tokens } of SUITES) {
    describe(`layerzero ${label} config`, () => {
        let config: LzConfig

        beforeAll(async () => {
            config = await build()
        })

        // Each token is a single hub-and-spoke pathway. A dropped entry is otherwise invisible until
        // wiring, when that lane simply never gets peered.
        it('declares one pathway per token', () => {
            expect(config.connections.length).toBeGreaterThanOrEqual(tokens)
            expect(config.contracts).toHaveLength(tokens * 2)
        })

        it('puts one contract per token on the hub', () => {
            expect(config.contracts.filter(({ contract }) => contract.eid === hubEid)).toHaveLength(tokens)
        })

        // A rename on one side alone fails `lz:oapp:wire` at its last step with "Could not find a
        // deployment", which is a slow way to learn about a typo.
        it('names hub contracts exactly as the deploy script names them', () => {
            const inConfig = config.contracts
                .filter(({ contract }) => contract.eid === hubEid)
                .map(({ contract }) => contract.contractName)
                .sort()

            expect(inConfig).toEqual(HUB_TOKENS[hubEid].map((token) => token.deployment).sort())
        })

        it('names spoke contracts as the deploy scripts name them', () => {
            const spokes = config.contracts
                .filter(({ contract }) => contract.eid !== hubEid && contract.eid !== solanaEid)
                .map(({ contract }) => contract.contractName)

            expect(spokes).toHaveLength(tokens - 2)
            for (const name of spokes) {
                expect(ADAPTER_DEPLOYMENTS).toContain(name)
            }
        })

        it('addresses Solana by address rather than deployment name', () => {
            const solana = config.contracts.filter(({ contract }) => contract.eid === solanaEid)

            expect(solana).toHaveLength(2)
            for (const { contract } of solana) {
                expect(contract.address).toBeTruthy()
                expect(contract.contractName).toBeUndefined()
            }
        })

        // V1 ids are 10xxx; every V2 id is 30xxx or 40xxx. Sepolia and Flare were both pinned to V1
        // ids before the topology change, and nothing failed until wiring.
        it('uses only V2 endpoint ids', () => {
            for (const { contract } of config.contracts) {
                expect(contract.eid).toBeGreaterThanOrEqual(30000)
            }
        })
    })
}

// The EVM-first configs exist so the Solana-free pathways can be wired on their own. Each has to stay
// a strict subset of its full config, or wiring it would set something the full run then has to undo.
const EVM_SUITES = [
    {
        label: 'mainnet',
        evm: mainnetEvmConfig as unknown as () => Promise<LzConfig>,
        full: mainnetConfig as unknown as () => Promise<LzConfig>,
        solanaEid: EndpointId.SOLANA_V2_MAINNET as number,
        pathways: 4,
    },
    {
        label: 'testnet',
        evm: evmConfig as unknown as () => Promise<LzConfig>,
        full: testnetConfig as unknown as () => Promise<LzConfig>,
        solanaEid: EndpointId.SOLANA_V2_TESTNET as number,
        pathways: 3,
    },
]

for (const suite of EVM_SUITES) {
    describe(`layerzero ${suite.label} EVM-only config`, () => {
        let evm: LzConfig
        let full: LzConfig

        beforeAll(async () => {
            evm = await suite.evm()
            full = await suite.full()
        })

        it('carries only the Solana-free pathways', () => {
            expect(evm.connections.length).toBeGreaterThanOrEqual(suite.pathways)
            expect(evm.contracts).toHaveLength(suite.pathways * 2)
        })

        it('touches no Solana endpoint', () => {
            for (const { contract } of evm.contracts) {
                expect(contract.eid).not.toBe(suite.solanaEid)
            }
        })

        it('names every contract the same way the full config does', () => {
            const names = (c: LzConfig) =>
                new Set(c.contracts.map(({ contract }) => contract.contractName).filter(Boolean))

            const fullNames = names(full)
            for (const name of names(evm)) {
                expect([...fullNames]).toContain(name)
            }
        })

        // Anything the EVM run sets that the full run sets differently gets flipped back and forth.
        it('configures every pathway exactly as the full config does', () => {
            for (const connection of evm.connections) {
                expect(full.connections).toContainEqual(connection)
            }
        })
    })
}

// A pathway left on fewer DVNs is the weakest lane in the mesh, and nothing fails to flag it.
describe('layerzero mainnet DVNs', () => {
    type UlnConfig = { requiredDVNs: string[]; optionalDVNs?: string[] }
    type Connection = { config?: { sendConfig?: { ulnConfig: UlnConfig }; receiveConfig?: { ulnConfig: UlnConfig } } }

    for (const [label, build] of [
        ['full', mainnetConfig],
        ['EVM-only', mainnetEvmConfig],
    ] as const) {
        it(`requires LayerZero Labs, Horizen and Canary on every ${label} pathway`, async () => {
            const { connections } = await (build as unknown as () => Promise<{ connections: Connection[] }>)()

            for (const { config } of connections) {
                for (const uln of [config?.sendConfig?.ulnConfig, config?.receiveConfig?.ulnConfig]) {
                    expect(uln?.requiredDVNs).toHaveLength(3)
                    expect(uln?.optionalDVNs ?? []).toHaveLength(0)
                }
            }
        })
    }
})

describe('hub token table', () => {
    const ALL_TOKENS = Object.values(HUB_TOKENS).flat()

    // Written once by `__OFT_init`, so a wrong value here is permanent for that deployment. Each pair
    // mirrors the token being represented: kHYPE, fXRP, cbBTC and wETH from their live home
    // contracts, SOL and jitoSOL from the Derive representations they replace.
    it('names each token as its home chain does', () => {
        const expected: Record<string, { name: string; symbol: string }> = {
            HYPE: { name: 'HYPE', symbol: 'HYPE' },
            KHYPE: { name: 'Kinetiq Staked HYPE', symbol: 'kHYPE' },
            SOL: { name: 'wSOL', symbol: 'wSOL' },
            JITOSOL: { name: 'jitoSOL', symbol: 'jitoSOL' },
            FXRP: { name: 'FXRP', symbol: 'FXRP' },
            CBBTC: { name: 'Coinbase Wrapped BTC', symbol: 'cbBTC' },
            WETH: { name: 'Wrapped Ether', symbol: 'WETH' },
        }

        for (const token of ALL_TOKENS) {
            expect({ name: token.name, symbol: token.symbol }).toEqual(expected[token.deployment])
        }
    })

    it('pairs each token with the OFT variant carrying its home chain decimals', () => {
        const expected: Record<string, string> = {
            HYPE: 'OFTToken18',
            KHYPE: 'OFTToken18',
            SOL: 'OFTToken9Seeded',
            JITOSOL: 'OFTToken9Seeded',
            FXRP: 'OFTToken6',
            CBBTC: 'OFTToken8',
            WETH: 'OFTToken18',
        }

        for (const token of ALL_TOKENS) {
            expect(token.contract).toBe(expected[token.deployment])
        }
    })

    it('keeps kHYPE off the mainnet hub', () => {
        const mainnet = HUB_TOKENS[EndpointId.ETHEREUM_V2_MAINNET].map((token) => token.deployment)

        expect(mainnet.sort()).toEqual(['CBBTC', 'FXRP', 'HYPE', 'JITOSOL', 'SOL', 'WETH'])
    })
})
