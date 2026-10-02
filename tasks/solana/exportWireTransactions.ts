import { writeFileSync } from 'fs'

import { PublicKey } from '@solana/web3.js'
import bs58 from 'bs58'
import { task } from 'hardhat/config'

import { type OmniTransaction } from '@layerzerolabs/devtools'
import { types as devtoolsTypes } from '@layerzerolabs/devtools-evm-hardhat'
import { deserializeTransactionMessage } from '@layerzerolabs/devtools-solana'
import { createLogger } from '@layerzerolabs/io-devtools'
import { ChainType, endpointIdToChainType, endpointIdToNetwork } from '@layerzerolabs/lz-definitions'
import { type OAppOmniGraph, configureOApp } from '@layerzerolabs/ua-devtools'
import { OAppOmniGraphHardhatSchema, SUBTASK_LZ_OAPP_CONFIG_LOAD } from '@layerzerolabs/ua-devtools-evm-hardhat'
import { initOFTAccounts } from '@layerzerolabs/ua-devtools-solana'

import { createSdkFactory, createSolanaConnectionFactory } from '../common/utils'

import { findSolanaEndpointIdInGraphOrNull, loadAllSolanaDeployments } from './utils'

const logger = createLogger()

interface Args {
    oappConfig: string
    admin: string
    output: string
}

/**
 * Lists, without sending, the Solana-side transactions that wire an OApp config, built for an admin
 * this machine holds no key for - a Squads vault. `lz:oapp:wire` builds its Solana instructions for
 * the local keypair, so they would name the wrong signer.
 *
 * Only connections leaving Solana are covered: the EVM side is the deployer's to wire as usual.
 */
task('lz:oft:solana:export-wire-txs', 'Writes the Solana-side wiring transactions for a multisig admin to a file')
    .addParam('oappConfig', 'Path to the LayerZero OApp config', undefined, devtoolsTypes.string)
    .addParam('admin', 'The OFT stores admin and delegate (e.g. a Squads vault)', undefined, devtoolsTypes.string)
    .addParam('output', 'File to write the transactions to', undefined, devtoolsTypes.string)
    .setAction(async ({ oappConfig, admin, output }: Args, hre) => {
        const adminKey = new PublicKey(admin)

        const solanaEid = await findSolanaEndpointIdInGraphOrNull(hre, oappConfig)
        if (solanaEid == null) throw new Error(`No Solana pathway in ${oappConfig}`)

        const programIds = new Map<string, PublicKey>()
        const tokens = new Map<string, string>()
        for (const [oftStore, { programId, token }] of loadAllSolanaDeployments(solanaEid)) {
            programIds.set(oftStore, new PublicKey(programId))
            tokens.set(oftStore, token)
        }

        const fullGraph: OAppOmniGraph = await hre.run(SUBTASK_LZ_OAPP_CONFIG_LOAD, {
            configPath: oappConfig,
            schema: OAppOmniGraphHardhatSchema,
            task: 'lz:oft:solana:export-wire-txs',
        })
        const graph: OAppOmniGraph = {
            ...fullGraph,
            connections: fullGraph.connections.filter(({ vector }) => vector.from.eid === solanaEid),
        }

        const sdkFactory = createSdkFactory(adminKey, programIds, createSolanaConnectionFactory())

        // Accounts first: the ULN config for a new remote has to exist before wiring can set it.
        const steps: [string, OmniTransaction[]][] = [
            ['init-config', await initOFTAccounts(graph, sdkFactory)],
            ['wire', await configureOApp(graph, sdkFactory)],
        ]

        const lines: string[] = [
            `Solana-side wiring for ${oappConfig}`,
            `Generated ${new Date().toISOString()} against ${endpointIdToNetwork(solanaEid)}. NOT SENT.`,
            ``,
            `Admin / delegate (signer of every instruction below): ${adminKey.toBase58()}`,
            `Execute in order. Each entry lists its instructions and a base58 transaction for Squads' import;`,
            `the blockhash inside it is stale by the time you read this, so Squads re-signs it fresh.`,
            ``,
        ]

        let index = 0
        const foreignSigners = new Set<string>()
        for (const [step, transactions] of steps) {
            lines.push(
                `${'='.repeat(100)}`,
                `STEP: ${step} (${transactions.length} transactions)`,
                `${'='.repeat(100)}`
            )
            if (transactions.length === 0) lines.push(`Nothing to do.`)

            for (const transaction of transactions) {
                if (endpointIdToChainType(transaction.point.eid) !== ChainType.SOLANA) continue

                const solanaTransaction = deserializeTransactionMessage(transaction.data)
                solanaTransaction.feePayer = adminKey

                index++
                lines.push(
                    ``,
                    `#${index} [${tokens.get(transaction.point.address) ?? transaction.point.address}] ${transaction.description ?? ''}`,
                    `  OFT store: ${transaction.point.address}`
                )

                solanaTransaction.instructions.forEach((instruction, i) => {
                    lines.push(`  instruction ${i + 1}: program ${instruction.programId.toBase58()}`)
                    for (const key of instruction.keys) {
                        const flags = [key.isSigner ? 'signer' : '', key.isWritable ? 'writable' : '']
                            .filter(Boolean)
                            .join(',')
                        lines.push(`    ${key.pubkey.toBase58()}${flags ? ` (${flags})` : ''}`)
                        if (key.isSigner && !key.pubkey.equals(adminKey)) foreignSigners.add(key.pubkey.toBase58())
                    }
                    lines.push(`    data (hex): ${instruction.data.toString('hex')}`)
                })

                lines.push(
                    `  base58 transaction: ${bs58.encode(
                        new Uint8Array(
                            solanaTransaction.serialize({ requireAllSignatures: false, verifySignatures: false })
                        )
                    )}`
                )
            }
        }

        if (foreignSigners.size > 0) {
            lines.push(``, `WARNING: instructions above also require these signers: ${[...foreignSigners].join(', ')}`)
        }

        writeFileSync(output, lines.join('\n') + '\n')
        logger.info(`Wrote ${index} Solana transactions to ${output}`)
        if (foreignSigners.size > 0) logger.warn(`Signers other than the admin required: ${[...foreignSigners]}`)
    })
