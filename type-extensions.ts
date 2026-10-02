import 'hardhat/types/config'

export interface OftAdapterConfig {
    /// Token this chain's adapter escrows.
    tokenAddress: string
    /// hardhat-deploy name for the adapter, e.g. 'FXRP_Adapter'.
    deploymentName: string
}

declare module 'hardhat/types/config' {
    interface HardhatNetworkUserConfig {
        oftAdapters?: never
    }

    interface HardhatNetworkConfig {
        oftAdapters?: never
    }

    interface HttpNetworkUserConfig {
        oftAdapters?: OftAdapterConfig[]
    }

    interface HttpNetworkConfig {
        oftAdapters?: OftAdapterConfig[]
    }
}
