// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/OFTDestination.sol";

/**
 * @title DeployDestination
 * @dev Script to deploy OFTDestination on the canonical destination chain
 */
contract DeployDestination is Script {
    function run() external {
        // Read environment variables
        string memory tokenName = vm.envString("TOKEN_NAME");
        string memory tokenSymbol = vm.envString("TOKEN_SYMBOL");
        address lzEndpoint = vm.envAddress("LZ_ENDPOINT");
        address owner = vm.envAddress("OWNER_ADDRESS");
        uint256 supplyCap = vm.envUint("SUPPLY_CAP"); // 0 for unlimited

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the destination OFT
        OFTDestination destination = new OFTDestination(lzEndpoint);

        // Initialize
        destination.initialize(tokenName, tokenSymbol, owner, supplyCap);

        console.log("OFTDestination deployed at:", address(destination));
        console.log("Token Name:", destination.name());
        console.log("Token Symbol:", destination.symbol());
        console.log("Supply Cap:", destination.supplyCap());
        console.log("Owner:", destination.owner());

        vm.stopBroadcast();
    }
}
