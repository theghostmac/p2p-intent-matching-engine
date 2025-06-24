// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../../src/IntentMatcher.sol";

contract DeployStrideIntentMatcher is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get environment variables
        address swapRouter = vm.envAddress("SWAP_ROUTER_ADDRESS");
        address owner = vm.envOr("OWNER_ADDRESS", deployer);

        console.log("Deploying with account:", deployer);
        console.log("Swap Router:", swapRouter);
        console.log("Owner:", owner);

        vm.startBroadcast(deployerPrivateKey);

        IntentMatcher matcher = new StrideIntentMatcher(swapRouter, owner);

        vm.stopBroadcast();

        console.log("StrideIntentMatcher deployed at:", address(matcher));

        // Save deployment info
        string memory json = "deployment";
        vm.serializeAddress(json, "matcher", address(matcher));
        vm.serializeAddress(json, "swapRouter", swapRouter);
        vm.serializeAddress(json, "owner", owner);
        string memory finalJson = vm.serializeAddress(json, "deployer", deployer);

        vm.writeJson(finalJson, "./deployments/latest.json");
    }
}
