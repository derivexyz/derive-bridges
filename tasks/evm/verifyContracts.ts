import { existsSync, readFileSync } from 'fs'
import { join } from 'path'

import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment } from 'hardhat/types'

import { createLogger } from '@layerzerolabs/io-devtools'

const logger = createLogger()

/// Etherscan's V2 API serves every chain it indexes from one host, picked by `chainid`. hardhat-deploy's
/// own etherscan-verify only speaks V1, so this submits the solc input it saved instead.
const ETHERSCAN_V2 = 'https://api.etherscan.io/v2/api'

const POLL_INTERVAL_MS = 5_000
const POLL_ATTEMPTS = 24

interface Explorer {
    url: string
    apiKey: string
}

interface SavedDeployment {
    address: string
    args?: unknown[]
    abi: { type: string; inputs?: unknown[] }[]
    metadata?: string
    solcInputHash?: string
}

async function explorerCall(explorer: Explorer, params: Record<string, string>, post = false) {
    const body = new URLSearchParams({ ...params, apikey: explorer.apiKey })
    const response = post
        ? await fetch(explorer.url, { method: 'POST', body })
        : await fetch(`${explorer.url}${explorer.url.includes('?') ? '&' : '?'}${body}`)

    return (await response.json()) as { status: string; message: string; result: string }
}

/// Resolves a submission guid to its final status, since both explorers verify asynchronously.
async function awaitGuid(explorer: Explorer, action: string, guid: string): Promise<string> {
    for (let attempt = 0; attempt < POLL_ATTEMPTS; attempt++) {
        await new Promise((resolve) => setTimeout(resolve, POLL_INTERVAL_MS))

        const { result } = await explorerCall(explorer, { module: 'contract', action, guid })
        if (!/pending|queue/i.test(result)) return result
    }

    return `still pending after ${(POLL_INTERVAL_MS * POLL_ATTEMPTS) / 1000}s (guid ${guid})`
}

function isVerified(result: string) {
    return /pass|already verified|successfully/i.test(result)
}

async function verifySource(hre: HardhatRuntimeEnvironment, explorer: Explorer, name: string, dir: string) {
    const deployment = JSON.parse(readFileSync(join(dir, `${name}.json`), 'utf8')) as SavedDeployment
    if (deployment.metadata == null || deployment.solcInputHash == null) {
        logger.warn(`${name}: no saved solc input, skipping`)
        return
    }

    const metadata = JSON.parse(deployment.metadata)
    const [sourceName, contractName] = Object.entries(metadata.settings.compilationTarget)[0] as [string, string]
    const solcInput = readFileSync(join(dir, 'solcInputs', `${deployment.solcInputHash}.json`), 'utf8')

    const constructorAbi = deployment.abi.find((item) => item.type === 'constructor')
    const constructorArgs = constructorAbi
        ? hre.ethers.utils.defaultAbiCoder.encode(
              // eslint-disable-next-line @typescript-eslint/no-explicit-any
              (constructorAbi.inputs ?? []) as any,
              deployment.args ?? []
          )
        : '0x'

    const submission = await explorerCall(
        explorer,
        {
            module: 'contract',
            action: 'verifysourcecode',
            contractaddress: deployment.address,
            sourceCode: solcInput,
            codeformat: 'solidity-standard-json-input',
            contractname: `${sourceName}:${contractName}`,
            compilerversion: `v${metadata.compiler.version}`,
            // Etherscan's spelling.
            constructorArguements: constructorArgs.slice(2),
        },
        true
    )

    const result =
        submission.status === '1'
            ? await awaitGuid(explorer, 'checkverifystatus', submission.result)
            : submission.result
    const message = `${name} ${deployment.address} (${contractName}): ${result}`
    if (isVerified(result)) logger.info(message)
    else logger.error(message)
}

/// Marks a proxy as one on the explorer, so its page reads and writes through the implementation ABI.
async function linkProxy(explorer: Explorer, name: string, dir: string) {
    const { address } = JSON.parse(readFileSync(join(dir, `${name}_Proxy.json`), 'utf8')) as SavedDeployment
    const submission = await explorerCall(
        explorer,
        { module: 'contract', action: 'verifyproxycontract', address },
        true
    )

    const result =
        submission.status === '1'
            ? await awaitGuid(explorer, 'checkproxyverification', submission.result)
            : submission.result
    logger.info(`${name}_Proxy ${address}: ${result}`)
}

task('lz:evm:verify', 'Verifies every saved deployment on this network on its block explorer')
    .addOptionalParam('only', 'Comma-separated deployment names to verify, e.g. HYPE,FXRP')
    .setAction(async ({ only }: { only?: string }, hre) => {
        const dir = join(hre.config.paths.root, 'deployments', hre.network.name)
        if (!existsSync(dir)) throw new Error(`No deployments for ${hre.network.name}`)

        // A network carrying a Blockscout apiUrl verifies there, keyless. Everything else goes through
        // Etherscan V2 on the one shared key.
        const blockscout = hre.network.config.verify?.etherscan?.apiUrl
        const { chainId } = await hre.ethers.provider.getNetwork()
        const explorer: Explorer = blockscout
            ? { url: `${blockscout.replace(/\/$/, '')}`, apiKey: hre.network.config.verify?.etherscan?.apiKey ?? '' }
            : { url: `${ETHERSCAN_V2}?chainid=${chainId}`, apiKey: process.env.ETHERSCAN_API_KEY ?? '' }

        if (!blockscout && !explorer.apiKey) throw new Error('Set ETHERSCAN_API_KEY to verify on Etherscan')

        // Combined deployments (e.g. `HYPE`) share the proxy's address, so verify their parts instead.
        const combined = Object.keys(await hre.deployments.all()).filter(
            (name) => existsSync(join(dir, `${name}_Proxy.json`)) && (only == null || only.split(',').includes(name))
        )

        for (const name of combined) {
            for (const part of ['Implementation', 'ProxyAdmin', 'Proxy']) {
                await verifySource(hre, explorer, `${name}_${part}`, dir)
            }
            // Blockscout detects proxies on its own.
            if (!blockscout) await linkProxy(explorer, name, dir)
        }
    })
