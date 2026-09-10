/// <reference types="jest" />

// The Solana task barrel reaches an ESM-only dependency that jest cannot transform, and these tests
// only care about the shape of the config. Real store addresses are covered by the fork tests.
jest.mock('../../tasks/solana', () => ({
    getOftStoreAddress: (eid: number, token: string) => `oft-store-${token}-${eid}`,
}))

import { EndpointId } from '@layerzerolabs/lz-definitions'

import { deploymentName as nativeAdapterDeployment } from '../../deploy/NativeTokenOFTAdapter'
import { HUB_TOKENS } from '../../deploy/TokenOFT'
import mainnetConfig from '../../layerzero.config'
import testnetConfig from '../../layerzero.testnet-config'
import evmConfig from '../../layerzero.testnet-evm-config'

// Adapter names come from `oftAdapter.deploymentName` in hardhat.config.ts. Duplicated here rather than
// importing the hardhat config, which would pull the whole plugin chain into jest.
const ADAPTER_DEPLOYMENTS = ['FXRP_Adapter', 'KHYPE_Adapter', nativeAdapterDeployment]

type OmniPoint = { eid: number; contractName?: string; address?: string }
type LzConfig = { contracts: { contract: OmniPoint }[]; connections: unknown[] }

const SUITES = [
    {
        label: 'mainnet',
        build: mainnetConfig as unknown as () => Promise<LzConfig>,
        hubEid: EndpointId.ETHEREUM_V2_MAINNET as number,
        solanaEid: EndpointId.SOLANA_V2_MAINNET as number,
    },
    {
        label: 'testnet',
        build: testnetConfig as unknown as () => Promise<LzConfig>,
        hubEid: EndpointId.SEPOLIA_V2_TESTNET as number,
        solanaEid: EndpointId.SOLANA_V2_TESTNET as number,
    },
]

for (const { label, build, hubEid, solanaEid } of SUITES) {
    describe(`layerzero ${label} config`, () => {
        let config: LzConfig

        beforeAll(async () => {
            config = await build()
        })

        // Five tokens, each a single hub-and-spoke pathway. A dropped entry is otherwise invisible
        // until wiring, when that lane simply never gets peered.
        it('declares one pathway per token', () => {
            expect(config.connections.length).toBeGreaterThanOrEqual(5)
            expect(config.contracts).toHaveLength(10)
        })

        it('puts exactly five contracts on the hub', () => {
            expect(config.contracts.filter(({ contract }) => contract.eid === hubEid)).toHaveLength(5)
        })

        // A rename on one side alone fails `lz:oapp:wire` at its last step with "Could not find a
        // deployment", which is a slow way to learn about a typo.
        it('names hub contracts exactly as the deploy script names them', () => {
            const inConfig = config.contracts
                .filter(({ contract }) => contract.eid === hubEid)
                .map(({ contract }) => contract.contractName)
                .sort()

            expect(inConfig).toEqual(HUB_TOKENS.map((token) => token.deployment).sort())
        })

        it('names spoke contracts as the deploy scripts name them', () => {
            const spokes = config.contracts
                .filter(({ contract }) => contract.eid !== hubEid && contract.eid !== solanaEid)
                .map(({ contract }) => contract.contractName)

            expect(spokes).toHaveLength(3)
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

// The EVM-first config exists so the three Solana-free pathways can be wired on their own. It has to
// stay a strict subset of the full testnet config, or wiring it would set something the full run then
// has to undo.
describe('layerzero testnet EVM-only config', () => {
    let evm: LzConfig
    let full: LzConfig

    beforeAll(async () => {
        evm = await (evmConfig as unknown as () => Promise<LzConfig>)()
        full = await (testnetConfig as unknown as () => Promise<LzConfig>)()
    })

    it('carries only the three Solana-free pathways', () => {
        expect(evm.connections.length).toBeGreaterThanOrEqual(3)
        expect(evm.contracts).toHaveLength(6)
    })

    it('touches no Solana endpoint', () => {
        for (const { contract } of evm.contracts) {
            expect(contract.eid).not.toBe(EndpointId.SOLANA_V2_TESTNET as number)
        }
    })

    it('names every contract the same way the full config does', () => {
        const names = (c: LzConfig) => new Set(c.contracts.map(({ contract }) => contract.contractName).filter(Boolean))

        const fullNames = names(full)
        for (const name of names(evm)) {
            expect([...fullNames]).toContain(name)
        }
    })
})

describe('hub token table', () => {
    // Written once by `__OFT_init`, so a wrong value here is permanent for that deployment. Each pair
    // mirrors the token being represented: kHYPE and fXRP from their live home contracts, SOL and
    // jitoSOL from the Derive representations they replace.
    it('names each token as its home chain does', () => {
        const expected: Record<string, { name: string; symbol: string }> = {
            HYPE: { name: 'HYPE', symbol: 'HYPE' },
            KHYPE: { name: 'Kinetiq Staked HYPE', symbol: 'kHYPE' },
            SOL: { name: 'wSOL', symbol: 'wSOL' },
            JITOSOL: { name: 'jitoSOL', symbol: 'jitoSOL' },
            FXRP: { name: 'FXRP', symbol: 'FXRP' },
        }

        for (const token of HUB_TOKENS) {
            expect({ name: token.name, symbol: token.symbol }).toEqual(expected[token.deployment])
        }
    })

    it('pairs each token with the OFT variant carrying its home chain decimals', () => {
        const expected: Record<string, string> = {
            HYPE: 'TokenOFT18',
            KHYPE: 'TokenOFT18',
            SOL: 'TokenOFT9',
            JITOSOL: 'TokenOFT9',
            FXRP: 'TokenOFT6',
        }

        for (const token of HUB_TOKENS) {
            expect(token.contract).toBe(expected[token.deployment])
        }
        expect(HUB_TOKENS).toHaveLength(Object.keys(expected).length)
    })
})
