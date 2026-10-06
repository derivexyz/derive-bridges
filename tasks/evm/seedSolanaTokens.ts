import { existsSync, readFileSync, writeFileSync } from 'fs'

import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import { createLogger } from '@layerzerolabs/io-devtools'
import { EndpointId } from '@layerzerolabs/lz-definitions'

const logger = createLogger()

const DERIVE_RPC = 'https://rpc.lyra.finance'
const ETHEREUM_RPC = 'https://ethereum-rpc.publicnode.com'
const ETHEREUM_CHAIN_ID = 1
const SOLANA_EID = EndpointId.SOLANA_V2_MAINNET

const ZERO_PEER = '0x0000000000000000000000000000000000000000000000000000000000000000'

/// Each Derive receiver and the hub deployment that replaces it.
const TOKENS = [
    { label: 'wSOL', deriveDeployment: 'SOL', hubDeployment: 'SOL' },
    { label: 'jitoSOL', deriveDeployment: 'JITO', hubDeployment: 'JITOSOL' },
]

const RECEIVER_ABI = ['function peers(uint32) view returns (bytes32)']
const ERC20_ABI = ['function totalSupply() view returns (uint256)', 'function decimals() view returns (uint8)']
const HUB_ABI = [
    'function seeded() view returns (bool)',
    'function owner() view returns (address)',
    'function decimals() view returns (uint8)',
    'function totalSupply() view returns (uint256)',
    'function seed(address _to, uint256 _amount)',
]

interface SafeTransaction {
    to: string
    value: string
    data: string
    contractMethod: null
    contractInputsValues: null
}

/**
 * Emits the Ethereum-side `seed` calls that reproduce Derive's supply on the hub.
 *
 * Only safe to run once the freeze has executed: `seed` is one-shot, so an amount read while Derive
 * could still mint or burn cannot be corrected afterwards. Every check below exists to refuse a batch
 * built on a number that can still move.
 */
async function buildSeed(
    hre: HardhatRuntimeEnvironment,
    args: { deriveRpc: string; ethereumRpc: string; deployments: string; to: string }
): Promise<{ transactions: SafeTransaction[]; owner: string; lines: string[] }> {
    const deriveProvider = new hre.ethers.providers.JsonRpcProvider(args.deriveRpc)
    const hubProvider = new hre.ethers.providers.JsonRpcProvider(args.ethereumRpc)
    const hubInterface = new hre.ethers.utils.Interface(HUB_ABI)

    const recipient = hre.ethers.utils.getAddress(args.to)
    const transactions: SafeTransaction[] = []
    const owners = new Set<string>()
    const lines: string[] = []

    for (const { label, deriveDeployment, hubDeployment } of TOKENS) {
        const derivePath = `deployments/derive-mainnet/${deriveDeployment}.json`
        const hubPath = `deployments/${args.deployments}/${hubDeployment}.json`
        for (const path of [derivePath, hubPath]) {
            if (!existsSync(path)) throw new Error(`Missing ${path}; cannot resolve ${label}`)
        }

        const { erc20, DeriveOFTReceiver: receiver } = JSON.parse(readFileSync(derivePath, 'utf8'))
        const { address: hub } = JSON.parse(readFileSync(hubPath, 'utf8'))

        // The freeze is what makes the amount below final. Without it this batch is guesswork.
        const peer = await new hre.ethers.Contract(receiver, RECEIVER_ABI, deriveProvider).peers(SOLANA_EID)
        if (peer !== ZERO_PEER) {
            throw new Error(
                `${label} is not frozen: peers(${SOLANA_EID}) on ${receiver} is still ${peer}. ` +
                    `Run lz:freeze:derive-solana and let it execute first.`
            )
        }

        const deriveToken = new hre.ethers.Contract(erc20, ERC20_ABI, deriveProvider)
        const hubToken = new hre.ethers.Contract(hub, HUB_ABI, hubProvider)

        const [outstanding, deriveDecimals, seeded, hubOwner, hubDecimals, hubSupply] = await Promise.all([
            deriveToken.totalSupply(),
            deriveToken.decimals(),
            hubToken.seeded(),
            hubToken.owner(),
            hubToken.decimals(),
            hubToken.totalSupply(),
        ])

        if (seeded) throw new Error(`${label} hub token ${hub} is already seeded`)

        // Amounts cross as raw integers, so a decimals mismatch would silently misprice the seed.
        if (deriveDecimals !== hubDecimals) {
            throw new Error(`${label} decimals differ: Derive ${deriveDecimals} vs hub ${hubDecimals}`)
        }

        // Seeding is meant to reproduce Derive's supply on a hub token that has none of its own. Any
        // existing supply means people have already bridged, and the two would compound.
        if (!hubSupply.isZero()) {
            throw new Error(
                `${label} hub token ${hub} already has supply ${hubSupply.toString()}; seeding would add to it`
            )
        }

        owners.add(hre.ethers.utils.getAddress(hubOwner))

        transactions.push({
            to: hre.ethers.utils.getAddress(hub),
            value: '0',
            data: hubInterface.encodeFunctionData('seed', [recipient, outstanding]),
            contractMethod: null,
            contractInputsValues: null,
        })

        lines.push(
            `${label}: seed ${hre.ethers.utils.formatUnits(outstanding, hubDecimals)} ` +
                `(${outstanding.toString()}) to ${recipient} on ${hub}`
        )
    }

    if (owners.size !== 1) {
        throw new Error(`Hub tokens have different owners (${[...owners].join(', ')}); they need separate batches`)
    }

    return { transactions, owner: [...owners][0], lines }
}

task('lz:seed:solana-tokens', 'Emit a Safe batch seeding the Ethereum wSOL and jitoSOL with their frozen Derive supply')
    .addParam('to', 'Address to receive the seeded supply, for onward distribution')
    .addOptionalParam('deriveRpc', 'Derive RPC endpoint', DERIVE_RPC)
    .addOptionalParam('ethereumRpc', 'Ethereum RPC endpoint', ETHEREUM_RPC)
    .addOptionalParam('deployments', 'Hub deployments directory', 'ethereum-mainnet')
    .addOptionalParam('out', 'Path for the Safe transaction-builder JSON', 'multisig/seed-solana-tokens.json')
    .setAction(async (args: Parameters<typeof buildSeed>[1] & { out: string }, hre) => {
        const { transactions, owner, lines } = await buildSeed(hre, args)

        for (const line of lines) logger.info(line)

        writeFileSync(
            args.out,
            JSON.stringify(
                {
                    version: '1.0',
                    chainId: String(ETHEREUM_CHAIN_ID),
                    createdAt: Date.now(),
                    meta: {
                        name: 'Seed wSOL and jitoSOL from frozen Derive supply',
                        description: lines.join('; '),
                        txBuilderVersion: '1.16.5',
                        createdFromSafeAddress: owner,
                    },
                    transactions,
                },
                null,
                2
            ) + '\n'
        )

        logger.info(`Wrote ${transactions.length} transactions to ${args.out}, to be signed by ${owner}`)
        logger.warn('Wire the Ethereum <-> Solana pathways only after this batch executes')
    })
