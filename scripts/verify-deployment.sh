#!/bin/bash

# Generic Contract Verification Script
# Verifies CREATE2 deployed contracts across multiple chains by comparing bytecode
# and optionally verifies contracts on Etherscan
# Usage: ./verify-deployment.sh <contract_address> <source_chain_id> <target_chain_id> [--verify-etherscan]

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
    echo "Usage: $0 <contract_address> <source_chain_id> <target_chain_id> [options]"
    echo ""
    echo "Examples:"
    echo "  $0 0x1234567890123456789012345678901234567890 42161 1"
    echo "  $0 0x9876543210987654321098765432109876543210 137 8453 --no-verify-etherscan"
    echo ""
    echo "Options:"
    echo "  --verify-etherscan       Fetch source code from source chain and verify on target chain (default)"
    echo "  --no-verify-etherscan    Skip Etherscan verification, only compare bytecode"
    echo ""
    echo "Note: Contract address should be the same on both chains (CREATE2 deployment)"
    echo "      For Etherscan verification, the contract must already be verified on the source chain"
    echo ""
    echo "Supported chain IDs:"
    echo "  - 1 (Ethereum)"
    echo "  - 10 (Optimism)"
    echo "  - 137 (Polygon)"
    echo "  - 8453 (Base)"
    echo "  - 42161 (Arbitrum)"
    echo ""
    echo "Environment variables for Etherscan verification:"
    echo "  SOURCE_ETHERSCAN_API_KEY - API key for source chain Etherscan (required)"
    echo "  TARGET_ETHERSCAN_API_KEY - API key for target chain Etherscan (required)"
    echo "  CONSTRUCTOR_ARGS         - ABI-encoded constructor arguments (optional)"
    echo "  VERIFIER_URL             - Target chain Etherscan verifier URL (optional, auto-detected)"
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

# Function to validate Ethereum address format
validate_address() {
    local address=$1
    if [[ ! "$address" =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        print_status $RED "Error: Invalid Ethereum address format: $address"
        return 1
    fi
    return 0
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

# Function to get verifier URL for chain
get_verifier_url() {
    case $1 in
        1) echo "https://api.etherscan.io/api" ;;
        10) echo "https://api-optimistic.etherscan.io/api" ;;
        137) echo "https://api.polygonscan.com/api" ;;
        8453) echo "https://api.basescan.org/api" ;;
        42161) echo "https://api.arbiscan.io/api" ;;
        *) echo "" ;;
    esac
}

# Function to fetch contract source code from Etherscan
fetch_contract_source() {
    local address=$1
    local chain_id=$2
    local api_key=$3
    
    local verifier_url=$(get_verifier_url "$chain_id")
    if [[ -z "$verifier_url" ]]; then
        print_status $RED "Error: No verifier URL available for chain ID $chain_id"
        return 1
    fi
    
    print_status $YELLOW "Fetching contract source from Etherscan..."
    
    local response=$(curl -s "${verifier_url}?module=contract&action=getsourcecode&address=${address}&apikey=${api_key}")
    
    # Check if response is valid JSON and has source code
    local source_code=$(echo "$response" | jq -r '.result[0].SourceCode' 2>/dev/null)
    local contract_name=$(echo "$response" | jq -r '.result[0].ContractName' 2>/dev/null)
    local compiler_version=$(echo "$response" | jq -r '.result[0].CompilerVersion' 2>/dev/null)
    
    if [[ "$source_code" == "null" || -z "$source_code" || "$source_code" == "" ]]; then
        print_status $RED "Error: Could not fetch source code from Etherscan"
        return 1
    fi
    
    # Export values for use by caller
    export FETCHED_SOURCE_CODE="$source_code"
    export FETCHED_CONTRACT_NAME="$contract_name"
    export FETCHED_COMPILER_VERSION="$compiler_version"
    
    print_status $GREEN "✓ Successfully fetched source code for contract: $contract_name"
    print_status $GREEN "✓ Compiler version: $compiler_version"
    
    return 0
}

# Function to verify contract using Etherscan API directly
verify_contract_with_source() {
    local address=$1
    local chain_id=$2
    local source_code=$3
    local contract_name=$4
    local compiler_version=$5
    local constructor_args=$6
    
    # Check required environment variables
    if [[ -z "$TARGET_ETHERSCAN_API_KEY" ]]; then
        print_status $RED "Error: TARGET_ETHERSCAN_API_KEY environment variable is required for verification"
        return 1
    fi
    
    # Determine verifier URL
    local verifier_url="$VERIFIER_URL"
    if [[ -z "$verifier_url" ]]; then
        verifier_url=$(get_verifier_url "$chain_id")
        if [[ -z "$verifier_url" ]]; then
            print_status $RED "Error: No verifier URL available for chain ID $chain_id"
            return 1
        fi
    fi
    
    print_status $BLUE "Verifying $contract_name at $address on chain $chain_id"
    print_status $BLUE "Using Etherscan API for verification..."
    
    # Clean up compiler version (remove 'v' prefix if present)
    local clean_compiler_version=$(echo "$compiler_version" | sed 's/^v//')
    
    # Submit verification request using form data
    local curl_cmd=(curl -s -X POST \
        -d "module=contract" \
        -d "action=verifysourcecode" \
        -d "contractaddress=$address" \
        -d "sourceCode=$source_code" \
        -d "contractname=$contract_name" \
        -d "compilerversion=$clean_compiler_version" \
        -d "apikey=$TARGET_ETHERSCAN_API_KEY")
    
    # Add constructor args if provided
    if [[ -n "$constructor_args" ]]; then
        curl_cmd+=(-d "constructorArguements=$constructor_args")
    fi
    
    curl_cmd+=("$verifier_url")
    
    local response=$("${curl_cmd[@]}")
    
    local status=$(echo "$response" | jq -r '.status' 2>/dev/null)
    local message=$(echo "$response" | jq -r '.message' 2>/dev/null)
    local result=$(echo "$response" | jq -r '.result' 2>/dev/null)
    
    if [[ "$status" == "1" ]]; then
        print_status $GREEN "✓ Verification request submitted successfully"
        print_status $BLUE "GUID: $result"
        print_status $YELLOW "You can check the verification status at the explorer"
        return 0
    else
        print_status $RED "❌ Verification request failed: $message"
        return 1
    fi
}

# Function to verify contract on Etherscan using fetched source
verify_contract_etherscan() {
    local address=$1
    local source_chain_id=$2
    local target_chain_id=$3
    
    print_status $YELLOW "Fetching contract source from source chain..."
    
    # Check required environment variables
    if [[ -z "$SOURCE_ETHERSCAN_API_KEY" ]]; then
        print_status $RED "Error: SOURCE_ETHERSCAN_API_KEY environment variable is required for verification"
        return 1
    fi
    
    if [[ -z "$TARGET_ETHERSCAN_API_KEY" ]]; then
        print_status $RED "Error: TARGET_ETHERSCAN_API_KEY environment variable is required for verification"
        return 1
    fi
    
    # Fetch source code from the source chain
    if ! fetch_contract_source "$address" "$source_chain_id" "$SOURCE_ETHERSCAN_API_KEY"; then
        print_status $RED "Failed to fetch source code from source chain"
        return 1
    fi
    
    # Use the fetched source code to verify on target chain
    if verify_contract_with_source "$address" "$target_chain_id" "$FETCHED_SOURCE_CODE" "$FETCHED_CONTRACT_NAME" "$FETCHED_COMPILER_VERSION" "$CONSTRUCTOR_ARGS"; then
        print_status $GREEN "✓ Contract verification successful on target chain"
        return 0
    else
        print_status $RED "❌ Contract verification failed on target chain"
        return 1
    fi
}

# Main function
main() {
    # Check if required tools are installed
    command -v jq >/dev/null 2>&1 || { print_status $RED "Error: jq is required but not installed."; exit 1; }
    command -v curl >/dev/null 2>&1 || { print_status $RED "Error: curl is required but not installed."; exit 1; }
    
    # Parse arguments
    local verify_etherscan=true
    local contract_address=""
    local source_chain=""
    local target_chain=""
    
    # Process arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --verify-etherscan)
                verify_etherscan=true
                shift
                ;;
            --no-verify-etherscan)
                verify_etherscan=false
                shift
                ;;
            -*)
                print_status $RED "Error: Unknown option $1"
                usage
                ;;
            *)
                if [[ -z "$contract_address" ]]; then
                    contract_address=$1
                elif [[ -z "$source_chain" ]]; then
                    source_chain=$1
                elif [[ -z "$target_chain" ]]; then
                    target_chain=$1
                else
                    print_status $RED "Error: Too many arguments"
                    usage
                fi
                shift
                ;;
        esac
    done
    
    # Check required arguments
    if [[ -z "$contract_address" || -z "$source_chain" || -z "$target_chain" ]]; then
        print_status $RED "Error: Missing required arguments"
        usage
    fi
    
    # Check for forge if etherscan verification is requested
    if [[ "$verify_etherscan" == true ]]; then
        command -v forge >/dev/null 2>&1 || { print_status $RED "Error: forge is required for Etherscan verification but not installed."; exit 1; }
    fi
    
    print_status $BLUE "=== CREATE2 Contract Verification ==="
    echo ""
    
    # Validate address
    validate_address "$contract_address" || exit 1
    
    # Verify CREATE2 contract across chains
    local source_chain_name=$(get_chain_name "$source_chain")
    local target_chain_name=$(get_chain_name "$target_chain")
    
    print_status $BLUE "Verifying CREATE2 contract deployment:"
    print_status $BLUE "Contract Address: $contract_address"
    print_status $BLUE "Source: $source_chain_name (Chain ID: $source_chain)"
    print_status $BLUE "Target: $target_chain_name (Chain ID: $target_chain)"
    echo ""
    
    # Get source contract bytecode
    print_status $YELLOW "Fetching source contract bytecode..."
    local source_rpc=$(get_rpc_url "$source_chain")
    local source_bytecode=$(get_bytecode "$source_rpc" "$contract_address")
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    
    print_status $GREEN "✓ Source bytecode: ${#source_bytecode} characters"
    echo ""
    
    # Get target contract bytecode
    print_status $YELLOW "Fetching target contract bytecode..."
    local target_rpc=$(get_rpc_url "$target_chain")
    local target_bytecode=$(get_bytecode "$target_rpc" "$contract_address")
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
    
    print_status $GREEN "✓ Target bytecode: ${#target_bytecode} characters"
    echo ""
    
    # Compare bytecode
    print_status $YELLOW "Comparing bytecode..."
    if compare_bytecode "$source_bytecode" "$target_bytecode"; then
        print_status $GREEN "🎉 SUCCESS: Bytecode matches perfectly!"
        print_status $GREEN "CREATE2 deployment verified - contracts are identical across both chains."
        
        # Perform Etherscan verification if requested
        if [[ "$verify_etherscan" == true ]]; then
            echo ""
            print_status $BLUE "=== Etherscan Verification ==="
            print_status $BLUE "Fetching source code from $source_chain_name and verifying on $target_chain_name"
            
            # Verify on target chain using source from source chain
            if verify_contract_etherscan "$contract_address" "$source_chain" "$target_chain"; then
                print_status $GREEN "✓ Contract verification completed on target chain"
            else
                print_status $YELLOW "⚠ Contract verification failed (contract may already be verified or have different constructor args)"
            fi
            
            echo ""
            print_status $GREEN "🎉 Etherscan verification process completed!"
        fi
    else
        print_status $RED "❌ FAILURE: Bytecode mismatch detected!"
        print_status $RED "The contracts have different bytecode at the same address."
        print_status $RED "Source length: ${#source_bytecode} characters"
        print_status $RED "Target length: ${#target_bytecode} characters"
        print_status $RED "This may indicate a deployment issue or different contract versions."
        exit 1
    fi
}

# Run main function with all arguments
main "$@"