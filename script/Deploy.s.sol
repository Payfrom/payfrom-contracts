// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {PayFromRouter} from "../src/PayFromRouter.sol";

contract DeployScript is Script {
    function run() external {
        // Load from environment variables
        address feeWallet = vm.envAddress("FEE_WALLET");
        address authorizedSigner = vm.envAddress("AUTHORIZED_SIGNER");
        address owner = vm.envAddress("OWNER_ADDRESS");
        
        // LiFi Diamond (same address on all chains)
        address[] memory initialExecutors = new address[](1);
        initialExecutors[0] = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;
        
        // Get USDC + USDT for current chain
        address[] memory initialTokens = getStablecoins();
        
        // Deploy
        vm.startBroadcast();
        
        PayFromRouter router = new PayFromRouter(
            feeWallet,
            authorizedSigner,
            initialExecutors,
            initialTokens,
            owner
        );
        
        vm.stopBroadcast();
        
        // Log deployment info
        console.log("====================================");
        console.log("Chain ID:", block.chainid);
        console.log("PayFromRouter deployed to:", address(router));
        console.log("Fee Wallet:", feeWallet);
        console.log("Authorized Signer:", authorizedSigner);
        console.log("Owner:", owner);
        console.log("Supported tokens:");
        for (uint i = 0; i < initialTokens.length; i++) {
            console.log("  -", initialTokens[i]);
        }
        console.log("====================================");
    }
    
    function getStablecoins() internal view returns (address[] memory) {
        uint256 chainId = block.chainid;
        address[] memory tokens = new address[](2);
        
        if (chainId == 137) {
            // Polygon Mainnet
            tokens[0] = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359; // USDC
            tokens[1] = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F; // USDT
        } else if (chainId == 8453) {
            // Base Mainnet
            tokens[0] = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // USDC
            tokens[1] = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2; // USDT
        } else if (chainId == 42161) {
            // Arbitrum Mainnet
            tokens[0] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC
            tokens[1] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT
        } else if (chainId == 10) {
            // Optimism Mainnet
            tokens[0] = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85; // USDC
            tokens[1] = 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58; // USDT
        } else if (chainId == 84532) {
            // Base Sepolia Testnet
            tokens[0] = 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // USDC
            tokens[1] = 0x0000000000000000000000000000000000000000; // USDT (placeholder - update if available)
        } else {
            revert("Unsupported chain");
        }
        
        return tokens;
    }
}