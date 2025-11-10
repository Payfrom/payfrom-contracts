// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Script.sol";
import "../src/PayFromRouter.sol";

contract DeployScript is Script {
    function run() external {
        // 1. Get the private key for the deployer's wallet
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // 2. The address corresponding to the private key is the DEPLOYER/OWNER
        address ownerAddress = vm.addr(deployerPrivateKey);
        
        // 3. Get the fee wallet address from environment variables
        address feeWallet = vm.envAddress("FEE_WALLET");

        vm.startBroadcast(deployerPrivateKey);
        
        // 4. Pass BOTH arguments: feeWallet and ownerAddress
        PayFromRouter router = new PayFromRouter(feeWallet, ownerAddress);
        
        console.log("PayFromRouter deployed to:", address(router));
        console.log("Contract Owner set to:", ownerAddress); // Optional: log the owner
        
        vm.stopBroadcast();
    }
}