// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/OFTSourceAdapter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title DeploySource
 * @dev Script to deploy OFTSourceAdapter on source chains
 */
contract DeploySource is Script {
    function run() external {
        // Read environment variables
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address lzEndpoint = vm.envAddress("LZ_ENDPOINT");
        uint32 destinationEid = uint32(vm.envUint("DESTINATION_EID"));
        address owner = vm.envAddress("OWNER_ADDRESS");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the source adapter
        OFTSourceAdapter adapter = new OFTSourceAdapter(tokenAddress, lzEndpoint, destinationEid);

        // Initialize with owner
        adapter.initialize(owner);

        console.log("OFTSourceAdapter deployed at:", address(adapter));
        console.log("Token:", adapter.token());
        console.log("Destination EID:", adapter.destinationEid());
        console.log("Owner:", adapter.owner());

        vm.stopBroadcast();
    }
}
