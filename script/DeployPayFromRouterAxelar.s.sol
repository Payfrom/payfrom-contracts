// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/Script.sol";
import "../src/PayFromRouterAxelar.sol";

/**
 * @title Deployment Script for PayFromRouterAxelar
 * @notice Deploys the Axelar-enabled PayFromRouter contract to testnet chains
 *
 * Usage:
 * forge script script/DeployPayFromRouterAxelar.s.sol:DeployPayFromRouterAxelar \
 *   --rpc-url $ETH_SEPOLIA_RPC \
 *   --private-key $PRIVATE_KEY \
 *   --broadcast \
 *   --verify \
 *   --etherscan-api-key $ETHERSCAN_API_KEY
 */
contract DeployPayFromRouterAxelar is Script {
    // Testnet addresses
    struct ChainConfig {
        address gateway;
        address gasService;
        address axlUSDC;
        string chainName;
    }

    function getChainConfig() internal view returns (ChainConfig memory) {
        uint256 chainId = block.chainid;

        if (chainId == 11155111) {
            // Ethereum Sepolia
            return ChainConfig({
                gateway: 0xe432150cce91c13a887f7D836923d5597adD8E31,
                gasService: 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6,
                axlUSDC: 0x254d06f33bDc5b8ee05b2ea472107E300226659A,
                chainName: "ethereum-sepolia"
            });
        } else if (chainId == 84532) {
            // Base Sepolia
            return ChainConfig({
                gateway: 0xe432150cce91c13a887f7D836923d5597adD8E31,
                gasService: 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6,
                axlUSDC: 0x88541670E55cC00bEEFD87eB59EDd1b7C511AC9a,
                chainName: "base-sepolia"
            });
        } else if (chainId == 421614) {
            // Arbitrum Sepolia
            return ChainConfig({
                gateway: 0xe432150cce91c13a887f7D836923d5597adD8E31,
                gasService: 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6,
                axlUSDC: 0x75Cc4fDf1ee3E781C1A3Ee9151D5c6Ce34Cf5C61,
                chainName: "arbitrum-sepolia"
            });
        } else if (chainId == 11155420) {
            // Optimism Sepolia
            return ChainConfig({
                gateway: 0xe432150cce91c13a887f7D836923d5597adD8E31,
                gasService: 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6,
                axlUSDC: 0x5fD84259d3C26C1B3b36a4FadE86E9B5fC5c7D2f,
                chainName: "optimism-sepolia"
            });
        } else if (chainId == 80002) {
            // Polygon Amoy
            return ChainConfig({
                gateway: 0xe432150cce91c13a887f7D836923d5597adD8E31,
                gasService: 0xbE406F0189A0B4cf3A05C286473D23791Dd44Cc6,
                axlUSDC: 0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582,
                chainName: "polygon-amoy"
            });
        } else {
            revert("Unsupported chain");
        }
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Get configuration for current chain
        ChainConfig memory config = getChainConfig();

        console.log("Deploying PayFromRouterAxelar on:", config.chainName);
        console.log("Deployer:", deployer);
        console.log("Gateway:", config.gateway);
        console.log("Gas Service:", config.gasService);
        console.log("axlUSDC:", config.axlUSDC);

        // Contract constructor parameters
        address feeWallet = vm.envOr("FEE_WALLET", deployer); // Default to deployer

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the contract
        PayFromRouterAxelar router = new PayFromRouterAxelar(
            feeWallet,
            deployer, // owner
            config.gateway,
            config.gasService
        );

        vm.stopBroadcast();

        console.log("PayFromRouterAxelar deployed at:", address(router));

        // Log configuration script
        console.log("\n=== POST-DEPLOYMENT CONFIGURATION ===");
        console.log("1. Set allowed chains:");

        if (block.chainid == 11155111) {
            // Ethereum Sepolia - allow other chains
            console.log("   router.setAllowedChains([\"base-sepolia\", \"arbitrum-sepolia\"], true)");
        } else if (block.chainid == 84532) {
            // Base Sepolia - allow other chains
            console.log("   router.setAllowedChains([\"ethereum-sepolia\", \"arbitrum-sepolia\"], true)");
        } else if (block.chainid == 421614) {
            // Arbitrum Sepolia - allow other chains
            console.log("   router.setAllowedChains([\"ethereum-sepolia\", \"base-sepolia\"], true)");
        }

        console.log("3. Update frontend configuration with deployed address:");
        console.log("   destinationRouterAddress:", address(router));

        // Save deployment info to file
        _saveDeploymentInfo(address(router), config);
    }

    function _saveDeploymentInfo(address routerAddress, ChainConfig memory config) internal {
        string memory deploymentInfo = string.concat(
            "{\n",
            '  "chainId": ', vm.toString(block.chainid), ",\n",
            '  "chainName": "', config.chainName, '",\n',
            '  "routerAddress": "', vm.toString(routerAddress), '",\n',
            '  "gateway": "', vm.toString(config.gateway), '",\n',
            '  "gasService": "', vm.toString(config.gasService), '",\n',
            '  "axlUSDC": "', vm.toString(config.axlUSDC), '",\n',
            '  "deployedAt": ', vm.toString(block.timestamp), "\n",
            "}"
        );

        string memory filename = string.concat(
            "deployments/",
            config.chainName,
            ".json"
        );

        vm.writeFile(filename, deploymentInfo);
        console.log("Deployment info saved to:", filename);
    }
}

/**
 * @title Configuration Script for PayFromRouterAxelar
 * @notice Configures trusted remote chains after deployment
 */
contract ConfigurePayFromRouterAxelar is Script {
    function run() external {
        address routerAddress = vm.envAddress("ROUTER_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        PayFromRouterAxelar router = PayFromRouterAxelar(payable(routerAddress));

        vm.startBroadcast(deployerPrivateKey);

        // Configure trusted remotes based on current chain
        string[] memory trustedChains = new string[](2);

        if (block.chainid == 11155111) {
            // Ethereum Sepolia
            trustedChains[0] = "base-sepolia";
            trustedChains[1] = "arbitrum-sepolia";
        } else if (block.chainid == 84532) {
            // Base Sepolia
            trustedChains[0] = "ethereum-sepolia";
            trustedChains[1] = "arbitrum-sepolia";
        } else if (block.chainid == 421614) {
            // Arbitrum Sepolia
            trustedChains[0] = "ethereum-sepolia";
            trustedChains[1] = "base-sepolia";
        } else {
            revert("Unsupported chain for configuration");
        }

        router.setAllowedChains(trustedChains, true);

        vm.stopBroadcast();

        console.log("Configured trusted remotes for router:", routerAddress);
        for (uint i = 0; i < trustedChains.length; i++) {
            console.log("  -", trustedChains[i]);
        }
    }
}