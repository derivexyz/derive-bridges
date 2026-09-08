import 'hardhat/types/config'

interface OftAdapterConfig {
    /// Token this chain's adapter escrows.
    tokenAddress: string
    /// hardhat-deploy name for the adapter, e.g. 'FXRP_Adapter'.
    deploymentName: string
}

declare module 'hardhat/types/config' {
    interface HardhatNetworkUserConfig {
        oftAdapter?: never
    }

    interface HardhatNetworkConfig {
        oftAdapter?: never
    }

    interface HttpNetworkUserConfig {
        oftAdapter?: OftAdapterConfig
    }

    interface HttpNetworkConfig {
        oftAdapter?: OftAdapterConfig
    }
}
