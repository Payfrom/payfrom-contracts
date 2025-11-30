#!/bin/bash

# PayFromRouter Axelar Deployment Script
# This script deploys the Axelar-enabled PayFromRouter to multiple testnet chains

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_PATH="script/DeployPayFromRouterAxelar.s.sol:DeployPayFromRouterAxelar"
CONFIG_SCRIPT_PATH="script/DeployPayFromRouterAxelar.s.sol:ConfigurePayFromRouterAxelar"

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found. Please copy .env.example to .env and configure it.${NC}"
    exit 1
fi

# Source the .env file
source .env

# Validate required environment variables
required_vars=("PRIVATE_KEY" "ETHERSCAN_API_KEY")
for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        echo -e "${RED}Error: $var is not set in .env file${NC}"
        exit 1
    fi
done

# Function to deploy to a specific chain
deploy_to_chain() {
    local chain_name=$1
    local rpc_var=$2
    local rpc_url=${!rpc_var}
    local etherscan_key_var=$3
    local etherscan_key=${!etherscan_key_var}

    echo -e "${BLUE}🚀 Deploying to $chain_name...${NC}"

    if [ -z "$rpc_url" ]; then
        echo -e "${YELLOW}⚠️  Warning: RPC URL for $chain_name not set, skipping...${NC}"
        return
    fi

    # Create deployments directory
    mkdir -p deployments

    # Deploy contract
    echo -e "${YELLOW}📋 Deploying contract...${NC}"
    forge script $SCRIPT_PATH \
        --rpc-url "$rpc_url" \
        --private-key "$PRIVATE_KEY" \
        --broadcast \
        --verify \
        --etherscan-api-key "$etherscan_key" \
        --legacy  # Use legacy transactions for better compatibility

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Deployment to $chain_name successful!${NC}"
    else
        echo -e "${RED}❌ Deployment to $chain_name failed!${NC}"
        return 1
    fi
}

# Function to configure trusted remotes
configure_chain() {
    local chain_name=$1
    local rpc_var=$2
    local rpc_url=${!rpc_var}
    local router_address=$3

    if [ -z "$router_address" ]; then
        echo -e "${YELLOW}⚠️  Warning: Router address not provided for $chain_name configuration${NC}"
        return
    fi

    echo -e "${BLUE}⚙️  Configuring trusted remotes for $chain_name...${NC}"

    ROUTER_ADDRESS=$router_address forge script $CONFIG_SCRIPT_PATH \
        --rpc-url "$rpc_url" \
        --private-key "$PRIVATE_KEY" \
        --broadcast \
        --legacy

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Configuration for $chain_name successful!${NC}"
    else
        echo -e "${RED}❌ Configuration for $chain_name failed!${NC}"
    fi
}

# Main deployment function
main() {
    echo -e "${GREEN}🔧 Starting PayFromRouter Axelar deployment...${NC}"
    echo "======================================================"

    # Check if forge is installed
    if ! command -v forge &> /dev/null; then
        echo -e "${RED}Error: Foundry (forge) is not installed. Please install it first.${NC}"
        exit 1
    fi

    # Check if we're in the right directory
    if [ ! -f "foundry.toml" ]; then
        echo -e "${RED}Error: Not in a Foundry project directory${NC}"
        exit 1
    fi

    # Build contracts first
    echo -e "${YELLOW}🔨 Building contracts...${NC}"
    forge build
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Build failed!${NC}"
        exit 1
    fi

    # Deploy to each chain
    if [ "$1" == "all" ] || [ "$1" == "" ]; then
        echo -e "${BLUE}📡 Deploying to all testnets...${NC}"

        deploy_to_chain "Ethereum Sepolia" "ETH_SEPOLIA_RPC" "ETHERSCAN_API_KEY"
        deploy_to_chain "Base Sepolia" "BASE_SEPOLIA_RPC" "ETHERSCAN_API_KEY"
        deploy_to_chain "Arbitrum Sepolia" "ARBITRUM_SEPOLIA_RPC" "ETHERSCAN_API_KEY"
        deploy_to_chain "Optimism Sepolia" "OP_SEPOLIA_RPC" "ETHERSCAN_API_KEY"
        deploy_to_chain "Polygon Amoy" "POLYGON_AMOY_RPC" "ETHERSCAN_API_KEY"

    elif [ "$1" == "ethereum" ]; then
        deploy_to_chain "Ethereum Sepolia" "ETH_SEPOLIA_RPC" "ETHERSCAN_API_KEY"
    elif [ "$1" == "base" ]; then
        deploy_to_chain "Base Sepolia" "BASE_SEPOLIA_RPC" "ETHERSCAN_API_KEY"
    elif [ "$1" == "arbitrum" ]; then
        deploy_to_chain "Arbitrum Sepolia" "ARBITRUM_SEPOLIA_RPC" "ETHERSCAN_API_KEY"
    elif [ "$1" == "optimism" ]; then
        deploy_to_chain "Optimism Sepolia" "OP_SEPOLIA_RPC" "ETHERSCAN_API_KEY"
    elif [ "$1" == "polygon" ]; then
        deploy_to_chain "Polygon Amoy" "POLYGON_AMOY_RPC" "ETHERSCAN_API_KEY"
    elif [ "$1" == "configure" ]; then
        echo -e "${BLUE}⚙️  Running configuration script...${NC}"
        echo "Make sure to set ROUTER_ADDRESS in .env file"

        if [ -z "$ROUTER_ADDRESS" ]; then
            echo -e "${RED}Error: ROUTER_ADDRESS not set in .env file${NC}"
            exit 1
        fi

        # Configure based on current network
        echo "Current ROUTER_ADDRESS: $ROUTER_ADDRESS"
        echo "Which network is this router on? (ethereum/base/arbitrum/optimism/polygon)"
        read -r network_choice

        case $network_choice in
            ethereum)
                configure_chain "Ethereum Sepolia" "ETH_SEPOLIA_RPC" "$ROUTER_ADDRESS"
                ;;
            base)
                configure_chain "Base Sepolia" "BASE_SEPOLIA_RPC" "$ROUTER_ADDRESS"
                ;;
            arbitrum)
                configure_chain "Arbitrum Sepolia" "ARBITRUM_SEPOLIA_RPC" "$ROUTER_ADDRESS"
                ;;
            optimism)
                configure_chain "Optimism Sepolia" "OP_SEPOLIA_RPC" "$ROUTER_ADDRESS"
                ;;
            polygon)
                configure_chain "Polygon Amoy" "POLYGON_AMOY_RPC" "$ROUTER_ADDRESS"
                ;;
            *)
                echo -e "${RED}Invalid network choice${NC}"
                exit 1
                ;;
        esac
    else
        echo -e "${RED}Invalid argument. Use: all, ethereum, base, arbitrum, optimism, polygon, or configure${NC}"
        exit 1
    fi

    echo "======================================================"
    echo -e "${GREEN}🎉 Deployment script completed!${NC}"

    if [ -d "deployments" ] && [ "$(ls -A deployments)" ]; then
        echo -e "${BLUE}📄 Deployment information saved in deployments/ directory${NC}"
        echo "Check the JSON files for deployed contract addresses"
    fi

    echo ""
    echo -e "${YELLOW}📋 Next steps:${NC}"
    echo "1. Update your frontend configuration with the deployed contract addresses"
    echo "2. Run './deploy.sh configure' to set up trusted remote chains"
    echo "3. Test cross-chain payments on testnet"
    echo "4. Add more supported tokens if needed using setTokens()"
}

# Help function
show_help() {
    echo "PayFromRouter Axelar Deployment Script"
    echo ""
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  all          Deploy to all supported testnets (default)"
    echo "  ethereum     Deploy to Ethereum Sepolia only"
    echo "  base         Deploy to Base Sepolia only"
    echo "  arbitrum     Deploy to Arbitrum Sepolia only"
    echo "  optimism     Deploy to Optimism Sepolia only"
    echo "  polygon      Deploy to Polygon Amoy only"
    echo "  configure    Configure trusted remote chains (requires ROUTER_ADDRESS in .env)"
    echo "  help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                  # Deploy to all testnets"
    echo "  $0 ethereum         # Deploy to Ethereum Sepolia only"
    echo "  $0 configure        # Configure trusted remotes"
}

# Check for help flag
if [ "$1" == "help" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    show_help
    exit 0
fi

# Run main function
main "$1"