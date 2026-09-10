import { existsSync, readFileSync, writeFileSync } from 'fs'

import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import { createLogger } from '@layerzerolabs/io-devtools'
import { EndpointId } from '@layerzerolabs/lz-definitions'

const logger = createLogger()

const DERIVE_RPC = 'https://rpc.lyra.finance'
const DERIVE_CHAIN_ID = 957
const SOLANA_EID = EndpointId.SOLANA_V2_MAINNET

const ZERO_PEER = '0x0000000000000000000000000000000000000000000000000000000000000000'

/// Derive-side receivers, read from the deployment records rather than hardcoded.
const TOKENS = [
    { label: 'wSOL', deployment: 'SOL' },
    { label: 'jitoSOL', deployment: 'JITO' },
]

const RECEIVER_ABI = [
    'function peers(uint32) view returns (bytes32)',
    'function owner() view returns (address)',
    'function lockedAmount(uint32) view returns (uint256)',
    'function setPeer(uint32 _eid, bytes32 _peer)',
]

const ERC20_ABI = ['function totalSupply() view returns (uint256)', 'function decimals() view returns (uint8)']

interface SafeTransaction {
    to: string
    value: string
    data: string
    contractMethod: null
    contractInputsValues: null
}

interface Frozen {
    label: string
    receiver: string
    erc20: string
    outstanding: string
    decimals: number
}

/**
 * Emits the Derive-side calls that freeze the Solana pathway.
 *
 * Supply figures are reported for context only. This batch executes long after it is generated, and
 * the pathway stays live until it does, so those numbers are stale by the time anyone signs. Read the
 * seed amount with `lz:seed:solana-tokens` once the freeze has actually landed.
 *
 * Unsetting the peer is the freeze: `_lzReceive` rejects an untrusted peer and `send` reverts without
 * one, so it stops both directions. `setWithdrawLimit` cannot do this - DeriveOFTReceiver skips its
 * rate-limit check entirely when the limit is zero, and whitelisted addresses bypass it regardless.
 *
 * The Solana side is not covered here: unsetting a peer on the OFT store is a Solana transaction, not
 * EVM calldata, and has to be signed separately.
 */
async function buildFreeze(
    hre: HardhatRuntimeEnvironment,
    rpcUrl: string
): Promise<{ transactions: SafeTransaction[]; frozen: Frozen[]; owner: string }> {
    const provider = new hre.ethers.providers.JsonRpcProvider(rpcUrl)
    const receiverInterface = new hre.ethers.utils.Interface(RECEIVER_ABI)

    const transactions: SafeTransaction[] = []
    const frozen: Frozen[] = []
    const owners = new Set<string>()

    for (const { label, deployment } of TOKENS) {
        const path = `deployments/derive-mainnet/${deployment}.json`
        if (!existsSync(path)) {
            throw new Error(`Missing ${path}; cannot resolve the ${label} receiver`)
        }
        const { erc20, DeriveOFTReceiver: receiver } = JSON.parse(readFileSync(path, 'utf8'))

        const receiverContract = new hre.ethers.Contract(receiver, RECEIVER_ABI, provider)
        const erc20Contract = new hre.ethers.Contract(erc20, ERC20_ABI, provider)

        const [peer, owner, locked, totalSupply, decimals] = await Promise.all([
            receiverContract.peers(SOLANA_EID),
            receiverContract.owner(),
            receiverContract.lockedAmount(SOLANA_EID),
            erc20Contract.totalSupply(),
            erc20Contract.decimals(),
        ])

        if (peer === ZERO_PEER) {
            throw new Error(`${label} is already frozen: peers(${SOLANA_EID}) is zero on ${receiver}`)
        }

        // The receiver mints and burns rather than escrowing, so every token in existence came through
        // it from Solana. A divergence means either the token has another minter or supply arrived from
        // another source chain - both of which would invalidate `totalSupply` as the seed amount.
        if (!locked.eq(totalSupply)) {
            throw new Error(
                `${label} accounting diverged: lockedAmount(${SOLANA_EID})=${locked.toString()} but ` +
                    `totalSupply=${totalSupply.toString()}. totalSupply is not a safe seed amount.`
            )
        }

        owners.add(hre.ethers.utils.getAddress(owner))

        transactions.push({
            to: hre.ethers.utils.getAddress(receiver),
            value: '0',
            data: receiverInterface.encodeFunctionData('setPeer', [SOLANA_EID, ZERO_PEER]),
            contractMethod: null,
            contractInputsValues: null,
        })

        frozen.push({
            label,
            receiver: hre.ethers.utils.getAddress(receiver),
            erc20: hre.ethers.utils.getAddress(erc20),
            outstanding: totalSupply.toString(),
            decimals,
        })
    }

    // One batch can only be signed by one Safe.
    if (owners.size !== 1) {
        throw new Error(`Receivers have different owners (${[...owners].join(', ')}); they need separate batches`)
    }

    return { transactions, frozen, owner: [...owners][0] }
}

task('lz:freeze:derive-solana', 'Emit a Safe batch that freezes the Derive <-> Solana pathway')
    .addOptionalParam('rpcUrl', 'Derive RPC endpoint', DERIVE_RPC)
    .addOptionalParam('out', 'Path for the Safe transaction-builder JSON', 'multisig/freeze-derive-solana.json')
    .setAction(async (args: { rpcUrl: string; out: string }, hre) => {
        const { transactions, frozen, owner } = await buildFreeze(hre, args.rpcUrl)

        for (const { label, outstanding, decimals, receiver } of frozen) {
            logger.info(`${label}: ${hre.ethers.utils.formatUnits(outstanding, decimals)} outstanding right now`)
            logger.info(`  receiver  ${receiver}`)
        }

        const description = frozen.map(({ label }) => `${label}: unset Solana peer`).join('; ')

        writeFileSync(
            args.out,
            JSON.stringify(
                {
                    version: '1.0',
                    chainId: String(DERIVE_CHAIN_ID),
                    createdAt: Date.now(),
                    meta: {
                        name: 'Freeze Derive <-> Solana bridge',
                        description,
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
        logger.warn('Solana-side peers are not in this batch and must be unset separately')
        logger.warn('Supply above is indicative only. It can move until this batch executes.')
        logger.warn('Get the seed amount from `lz:seed:solana-tokens` after the freeze has landed.')
    })
