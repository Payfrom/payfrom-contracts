// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {PayFromRouter} from "../src/PayFromRouter.sol";

contract DeployScript is Script {
    // Mainnet token addresses
    address constant USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT_MAINNET = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    
    // Base token addresses
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDT_BASE = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
    
    // Arbitrum token addresses
    address constant USDC_ARBITRUM = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant USDT_ARBITRUM = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    
    // Polygon token addresses
    address constant USDC_POLYGON = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address constant USDT_POLYGON = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    
    // Optimism token addresses
    address constant USDC_OPTIMISM = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address constant USDT_OPTIMISM = 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58;

    function run() external {
        // 1. Get the private key for the deployer's wallet
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // 2. The address corresponding to the private key is the DEPLOYER/owner
        address ownerAddress = vm.addr(deployerPrivateKey);
        
        // 3. Get the fee wallet address from environment variables
        address feeWallet = vm.envAddress("FEE_WALLET");
        
        // 4. Get chain ID to determine which tokens to whitelist
        uint256 chainId = block.chainid;

        console.log("=== Deployment Configuration ===");
        console.log("Chain ID:", chainId);
        console.log("Deployer/Owner:", ownerAddress);
        console.log("Fee Wallet:", feeWallet);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);
        
        // 5. Deploy the PayFromRouter contract
        PayFromRouter router = new PayFromRouter(feeWallet, ownerAddress);
        
        console.log("=== Deployment Successful ===");
        console.log("PayFromRouter deployed to:", address(router));
        console.log("");
        
        // 6. Add default supported tokens based on chain
        console.log("=== Whitelisting Tokens ===");
        
        if (chainId == 1) {
            // Ethereum Mainnet
            router.addSupportedToken(USDC_MAINNET);
            router.addSupportedToken(USDT_MAINNET);
            console.log("USDC (Mainnet) whitelisted:", USDC_MAINNET);
            console.log("USDT (Mainnet) whitelisted:", USDT_MAINNET);
        } else if (chainId == 8453) {
            // Base
            router.addSupportedToken(USDC_BASE);
            router.addSupportedToken(USDT_BASE);
            console.log("USDC (Base) whitelisted:", USDC_BASE);
            console.log("USDT (Base) whitelisted:", USDT_BASE);
        } else if (chainId == 42161) {
            // Arbitrum One
            router.addSupportedToken(USDC_ARBITRUM);
            router.addSupportedToken(USDT_ARBITRUM);
            console.log("USDC (Arbitrum) whitelisted:", USDC_ARBITRUM);
            console.log("USDT (Arbitrum) whitelisted:", USDT_ARBITRUM);
        } else if (chainId == 137) {
            // Polygon
            router.addSupportedToken(USDC_POLYGON);
            router.addSupportedToken(USDT_POLYGON);
            console.log("USDC (Polygon) whitelisted:", USDC_POLYGON);
            console.log("USDT (Polygon) whitelisted:", USDT_POLYGON);
        } else if (chainId == 10) {
            // Optimism
            router.addSupportedToken(USDC_OPTIMISM);
            router.addSupportedToken(USDT_OPTIMISM);
            console.log("USDC (Optimism) whitelisted:", USDC_OPTIMISM);
            console.log("USDT (Optimism) whitelisted:", USDT_OPTIMISM);
        } else {
            // use environment variables for test tokens
            address testUsdc = vm.envOr("TEST_USDC", address(0));
            address testUsdt = vm.envOr("TEST_USDT", address(0));
            
            if (testUsdc != address(0)) {
                router.addSupportedToken(testUsdc);
                console.log("Test USDC whitelisted:", testUsdc);
            }
            
            if (testUsdt != address(0)) {
                router.addSupportedToken(testUsdt);
                console.log("Test USDT whitelisted:", testUsdt);
            }
            
            if (testUsdc == address(0) && testUsdt == address(0)) {
                console.log("WARNING: No test tokens specified.");
                console.log("Set TEST_USDC and TEST_USDT in .env to whitelist test tokens.");
            }
        }
        
        vm.stopBroadcast();
        
        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("Contract owner:", router.owner());
        console.log("Fee wallet:", router.feeWallet());
        console.log("Max payment:", router.maxPayment());
        console.log("");
        console.log("=== Verification Command ===");
        console.log("forge verify-contract", address(router), "src/PayFromRouter.sol:PayFromRouter");
        console.log("  --chain-id", chainId);
        console.log("  --constructor-args $(cast abi-encode \"constructor(address,address)\"", feeWallet, ownerAddress, ")");
        console.log("  --etherscan-api-key $ETHERSCAN_API_KEY");
        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Verify the contract on block explorer");
        console.log("2. Test a small payment transaction");
        console.log("3. Monitor events for successful payments");
        console.log("4. Add additional tokens if needed:");
        console.log("   cast send", address(router), "\"addSupportedToken(address)\" <TOKEN_ADDRESS> --private-key $PRIVATE_KEY");
    }
}