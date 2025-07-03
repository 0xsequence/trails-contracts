# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Core Foundry Commands
- `forge build` - Compile contracts
- `forge test` - Run test suite
- `forge fmt` - Format Solidity code
- `forge snapshot` - Generate gas usage snapshots
- `forge script <script_path> --rpc-url <url> --broadcast --verify` - Deploy contracts

### Dependency Management
- `make install` or `make` - Install dependencies and update git submodules
- `make update-submodules` - Update submodules to latest versions
- `make reset-submodules` - Reset submodules to checked-in versions

### Testing Specific Components
- `forge test --match-contract <ContractName>` - Run tests for specific contract
- `forge test --match-test <testFunction>` - Run specific test function
- `forge test -vvvv` - Run tests with maximum verbosity for debugging

### Deployment
Deployment scripts are in `script/` directory. Required environment variables:
- `PRIVATE_KEY` - Deployer private key
- `RPC_URL` - Network RPC endpoint
- `ETHERSCAN_API_KEY` - For contract verification
- `CHAIN_ID` - Target chain ID
- `VERIFIER_URL` - Etherscan verifier URL
- `ADDRESS` - Sender address

## Architecture Overview

### Core Components

This is a Solidity project implementing **Sapient Signer modules** for Sequence v3 wallets, focusing on cross-chain payment and bridging functionality through LiFi and relay protocols.

#### Primary Contracts
- **TrailsLiFiSapientSigner** (`src/TrailsLiFiSapientSigner.sol`) - Validates LiFi protocol operations (swaps/bridges) via off-chain attestations. Targets a specific immutable `TARGET_LIFI_DIAMOND` address for security.
- **TrailsRelaySapientSigner** (`src/TrailsRelaySapientSigner.sol`) - Validates relay operations through similar attestation mechanism.
- **TrailsTokenSweeper** (`src/TrailsTokenSweeper.sol`) - Utility contract for token recovery operations.

#### Library Architecture
The project uses a modular library approach under `src/libraries/`:

**Execution Info Management:**
- `TrailsExecutionInfoInterpreter.sol` - Standardizes cross-chain execution data
- `TrailsExecutionInfoParams.sol` - Parameter handling for execution info

**LiFi Integration:**
- `TrailsLiFiFlagDecoder.sol` - Decodes LiFi call data using flag-based strategies
- `TrailsLiFiInterpreter.sol` - Interprets and validates LiFi operations
- `TrailsLiFiValidator.sol` - Validation logic for LiFi transactions

**Relay Integration:**
- `TrailsRelayDecoder.sol` - Decodes relay call data
- `TrailsRelayInterpreter.sol` - Interprets relay operations
- `TrailsRelayValidator.sol` - Validation logic for relay transactions
- `TrailsRelayParams.sol` - Parameter handling for relay operations

#### Interface Definitions
- `TrailsExecutionInfo.sol` - Core execution info structure
- `TrailsLiFi.sol` - LiFi-specific interfaces and decoding strategies
- `TrailsRelay.sol` - Relay-specific interfaces

### Key Architecture Patterns

**Sapient Signer Integration:** Both main contracts implement `ISapient` interface and integrate with Sequence wallet configuration trees as "Sapient Signer Leaves". They validate off-chain attestations to authorize operations without requiring direct wallet pre-approval.

**Validation Flow:**
1. Contract receives payload and encoded signature (attestation)
2. Validates target addresses match immutable contract addresses
3. Recovers attestation signer from signature
4. Decodes and interprets operation data using libraries
5. Computes intent hash from operations + signer
6. Returns hash for comparison against wallet's configured `imageHash`

**Security Model:** Each contract is deployed with immutable target addresses to prevent authorization of calls to arbitrary contracts. All validation is stateless and deterministic.

### External Dependencies
- **Sequence Wallet v3** - Core wallet infrastructure and payload handling
- **OpenZeppelin** - Cryptographic utilities (ECDSA, MessageHashUtils)
- **LiFi Protocol** - Cross-chain bridge/swap interfaces
- **ERC2470** - Singleton deployment pattern

### Testing Structure
Tests mirror the source structure with unit tests for libraries and integration tests for main contracts. Mock contracts in `test/mocks/` simulate external protocol interactions.

### Deployment Pattern
Uses singleton deployment via ERC2470 for deterministic addresses across chains. Deployment scripts handle environment variable configuration and verification automatically.