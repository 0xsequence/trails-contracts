#!/bin/bash

# Anypay Contract Verification Script
# Verifies deployed contracts across multiple chains by comparing bytecode
# Usage: ./verify-deployment.sh <contract_name> <source_chain_id> <target_chain_id>

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to print usage
usage() {
    echo "Usage: $0 <contract_name> <source_chain_id> <target_chain_id>"
    echo ""
    echo "Examples:"
    echo "  $0 AnypayRelaySapientSigner 42161 1"
    echo "  $0 AnypayLifiSapientSigner 137 8453"
    echo ""
    echo "Available contracts:"
    echo "  - AnypayRelaySapientSigner"
    echo "  - AnypayLifiSapientSigner"
    echo "  - AnypayLifiModifierWrapper"
    echo ""
    echo "Supported chain IDs:"
    echo "  - 1 (Ethereum)"
    echo "  - 10 (Optimism)"
    echo "  - 137 (Polygon)"
    echo "  - 8453 (Base)"
    echo "  - 42161 (Arbitrum)"
    exit 1
}

# Function to get chain name from chain ID
get_chain_name() {
    case $1 in
        1) echo "Ethereum" ;;
        10) echo "Optimism" ;;
        137) echo "Polygon" ;;
        8453) echo "Base" ;;
        42161) echo "Arbitrum" ;;
        *) echo "Unknown" ;;
    esac
}

# Function to get RPC URL from .envrc based on chain ID
get_rpc_url() {
    case $1 in
        1) echo "https://eth.llamarpc.com/api" ;;
        10) echo "https://optimism-rpc.publicnode.com" ;;
        137) echo "https://polygon.lava.build" ;;
        8453) echo "https://base.llamarpc.com" ;;
        42161) echo "https://arb1.arbitrum.io/rpc" ;;
        *) echo "" ;;
    esac
}

# Function to get contract address from broadcast file
get_contract_address() {
    local contract_name=$1
    local chain_id=$2
    local broadcast_file="broadcast/${contract_name}.s.sol/${chain_id}/run-latest.json"
    
    if [[ ! -f "$broadcast_file" ]]; then
        print_status $RED "Error: Broadcast file not found: $broadcast_file"
        return 1
    fi
    
    local address=$(jq -r '.transactions[0].contractAddress' "$broadcast_file" 2>/dev/null)
    if [[ "$address" == "null" || -z "$address" ]]; then
        print_status $RED "Error: Could not extract contract address from $broadcast_file"
        return 1
    fi
    
    echo "$address"
}

# Function to get bytecode from blockchain
get_bytecode() {
    local rpc_url=$1
    local address=$2
    
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"$address\",\"latest\"],\"id\":1}" \
        "$rpc_url")
    
    local bytecode=$(echo "$response" | jq -r '.result' 2>/dev/null)
    if [[ "$bytecode" == "null" || -z "$bytecode" || "$bytecode" == "0x" ]]; then
        print_status $RED "Error: Could not retrieve bytecode from $rpc_url for address $address"
        return 1
    fi
    
    echo "$bytecode"
}

# Function to compare bytecode
compare_bytecode() {
    local source_bytecode=$1
    local target_bytecode=$2
    
    if [[ "$source_bytecode" == "$target_bytecode" ]]; then
        return 0
    else
        return 1
    fi
}

# Main function
main() {
    # Check if required tools are installed
    command -v jq >/dev/null 2>&1 || { print_status $RED "Error: jq is required but not installed."; exit 1; }
    command -v curl >/dev/null 2>&1 || { print_status $RED "Error: curl is required but not installed."; exit 1; }
    
    # Check arguments
    if [[ $# -lt 2 ]]; then
        usage
    fi
    
    local contract_name=$1
    local source_chain=$2
    local target_chain=${3:-""}
    
    print_status $BLUE "=== Anypay Contract Verification ==="
    echo ""
    
    # If no target chain specified, verify all available chains
    if [[ -z "$target_chain" ]]; then
        print_status $YELLOW "No target chain specified. Verifying against all available chains..."
        echo ""
        
        # Find all available chains for this contract
        local broadcast_dir="broadcast/${contract_name}.s.sol"
        if [[ ! -d "$broadcast_dir" ]]; then
            print_status $RED "Error: No broadcast directory found for $contract_name"
            exit 1
        fi
        
        local source_chain_name=$(get_chain_name "$source_chain")
        print_status $BLUE "Source: $source_chain_name (Chain ID: $source_chain)"
        
        # Get source contract details
        local source_address=$(get_contract_address "$contract_name" "$source_chain")
        if [[ $? -ne 0 ]]; then
            exit 1
        fi
        
        local source_rpc=$(get_rpc_url "$source_chain")
        local source_bytecode=$(get_bytecode "$source_rpc" "$source_address")
        if [[ $? -ne 0 ]]; then
            exit 1
        fi
        
        print_status $GREEN "✓ Source contract found at: $source_address"
        print_status $GREEN "✓ Source bytecode retrieved (${#source_bytecode} characters)"
        echo ""
        
        # Compare with all other chains
        local verified_count=0
        local total_count=0
        
        for chain_dir in "$broadcast_dir"/*; do
            if [[ -d "$chain_dir" ]]; then
                local chain_id=$(basename "$chain_dir")
                
                # Skip source chain
                if [[ "$chain_id" == "$source_chain" ]]; then
                    continue
                fi
                
                total_count=$((total_count + 1))
                local chain_name=$(get_chain_name "$chain_id")
                
                print_status $YELLOW "Verifying against $chain_name (Chain ID: $chain_id)..."
                
                # Get target contract details
                local target_address=$(get_contract_address "$contract_name" "$chain_id")
                if [[ $? -ne 0 ]]; then
                    print_status $RED "✗ Failed to get contract address"
                    echo ""
                    continue
                fi
                
                local target_rpc=$(get_rpc_url "$chain_id")
                local target_bytecode=$(get_bytecode "$target_rpc" "$target_address")
                if [[ $? -ne 0 ]]; then
                    print_status $RED "✗ Failed to get bytecode"
                    echo ""
                    continue
                fi
                
                # Compare bytecode
                if compare_bytecode "$source_bytecode" "$target_bytecode"; then
                    print_status $GREEN "✓ Bytecode matches! Contract verified at: $target_address"
                    verified_count=$((verified_count + 1))
                else
                    print_status $RED "✗ Bytecode mismatch! Contract at: $target_address"
                    print_status $RED "  Source bytecode length: ${#source_bytecode}"
                    print_status $RED "  Target bytecode length: ${#target_bytecode}"
                fi
                echo ""
            fi
        done
        
        # Summary
        print_status $BLUE "=== Verification Summary ==="
        print_status $GREEN "Verified: $verified_count/$total_count chains"
        
        if [[ $verified_count -eq $total_count ]]; then
            print_status $GREEN "🎉 All deployments verified successfully!"
            exit 0
        else
            print_status $YELLOW "⚠️  Some deployments have mismatched bytecode"
            exit 1
        fi
        
    else
        # Verify specific source vs target chain
        local source_chain_name=$(get_chain_name "$source_chain")
        local target_chain_name=$(get_chain_name "$target_chain")
        
        print_status $BLUE "Verifying $contract_name deployment:"
        print_status $BLUE "Source: $source_chain_name (Chain ID: $source_chain)"
        print_status $BLUE "Target: $target_chain_name (Chain ID: $target_chain)"
        echo ""
        
        # Get source contract details
        print_status $YELLOW "Fetching source contract details..."
        local source_address=$(get_contract_address "$contract_name" "$source_chain")
        if [[ $? -ne 0 ]]; then
            exit 1
        fi
        
        local source_rpc=$(get_rpc_url "$source_chain")
        local source_bytecode=$(get_bytecode "$source_rpc" "$source_address")
        if [[ $? -ne 0 ]]; then
            exit 1
        fi
        
        print_status $GREEN "✓ Source contract: $source_address"
        print_status $GREEN "✓ Source bytecode: ${#source_bytecode} characters"
        echo ""
        
        # Get target contract details
        print_status $YELLOW "Fetching target contract details..."
        local target_address=$(get_contract_address "$contract_name" "$target_chain")
        if [[ $? -ne 0 ]]; then
            exit 1
        fi
        
        local target_rpc=$(get_rpc_url "$target_chain")
        local target_bytecode=$(get_bytecode "$target_rpc" "$target_address")
        if [[ $? -ne 0 ]]; then
            exit 1
        fi
        
        print_status $GREEN "✓ Target contract: $target_address"
        print_status $GREEN "✓ Target bytecode: ${#target_bytecode} characters"
        echo ""
        
        # Compare bytecode
        print_status $YELLOW "Comparing bytecode..."
        if compare_bytecode "$source_bytecode" "$target_bytecode"; then
            print_status $GREEN "🎉 SUCCESS: Bytecode matches perfectly!"
            print_status $GREEN "The contracts are identical across both chains."
        else
            print_status $RED "❌ FAILURE: Bytecode mismatch detected!"
            print_status $RED "The contracts have different bytecode."
            print_status $RED "Source length: ${#source_bytecode} characters"
            print_status $RED "Target length: ${#target_bytecode} characters"
            exit 1
        fi
    fi
}

# Run main function with all arguments
main "$@"