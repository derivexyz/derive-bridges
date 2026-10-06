import assert from 'assert'

import { type HardhatRuntimeEnvironment } from 'hardhat/types'

import { CHAIN_IDS, EthersSigner, useBigBlock, useSmallBlock } from '@layerzerolabs/hyperliquid-composer'

/**
 * Runs `deploy` inside a HyperEVM big block window, and is a no-op off HyperEVM.
 *
 * Small blocks cap gas far below what an OFT implementation needs, so a deploy submitted on them
 * never lands. Big blocks mine roughly once a minute, hence switching back straight after.
 */
export async function withBigBlock<T>(hre: HardhatRuntimeEnvironment, deploy: () => Promise<T>): Promise<T> {
    const { chainId } = await hre.ethers.provider.getNetwork()

    const isTestnet = chainId === CHAIN_IDS.TESTNET
    if (chainId !== CHAIN_IDS.MAINNET && !isTestnet) {
        return deploy()
    }

    const privateKey = hre.network.config.accounts
    assert(privateKey, `Missing accounts for ${hre.network.name} in hardhat.config.ts`)

    const signer = new EthersSigner(privateKey.toString())
    const logLevel = hre.hardhatArguments.verbose ? 'debug' : 'info'

    console.log(`Switching ${hre.network.name} to big blocks; expect roughly a minute per transaction`)
    await useBigBlock(signer, isTestnet, logLevel, true)

    try {
        return await deploy()
    } finally {
        // Restored even when the deploy throws, so a failure does not strand the deployer on
        // minute-long blocks.
        console.log(`Restoring ${hre.network.name} to small blocks`)
        await useSmallBlock(signer, isTestnet, logLevel, true)
    }
}
