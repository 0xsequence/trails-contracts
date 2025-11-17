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

This is a Solidity project implementing cross-chain payment and bridging functionality through TrailsRouter and TrailsIntentEntrypoint for Sequence v3 wallets.

#### Primary Contracts
- **TrailsRouter** (`src/TrailsRouter.sol`) - Consolidated router contract combining multicall routing, balance injection, and token sweeping functionality. Executes via delegatecall from Sequence v3 wallets.
- **TrailsRouterShim** (`src/TrailsRouterShim.sol`) - Lightweight shim that wraps router calls and records execution success using storage sentinels.
- **TrailsIntentEntrypoint** (`src/TrailsIntentEntrypoint.sol`) - EIP-712 signature-based entrypoint for depositing tokens to intent addresses with user authorization.

#### Library Architecture
The project uses a modular library approach under `src/libraries/`:

**Sentinel Management:**
- `TrailsSentinelLib.sol` - Manages storage sentinels for conditional execution tracking using tstore/sstore

### Key Architecture Patterns

**Delegatecall-Only Execution:** TrailsRouter and TrailsRouterShim are designed to execute only via delegatecall from Sequence v3 wallets. Direct calls are blocked via `onlyDelegatecall` modifier.

**Success Sentinel Pattern:** Operations track success/failure via storage sentinels keyed by `opHash`. This enables conditional fee collection and fallback refund logic.

**Balance Injection:** Runtime balance injection allows protocols to receive exact token amounts when bridge amounts are unknown beforehand (due to slippage and fees).

**EIP-712 Intent Authorization:** TrailsIntentEntrypoint uses EIP-712 signatures to authorize deposits to intent addresses, preventing replay attacks via nonce tracking.


### External Dependencies
- **Sequence Wallet v3** (`wallet-contracts-v3`) - Core wallet infrastructure and payload handling (`IDelegatedExtension`)
- **OpenZeppelin** (`openzeppelin-contracts`) - Token standards (IERC20, IERC20Permit), SafeERC20, cryptographic utilities (ECDSA), and security (ReentrancyGuard)
- **Tstorish** (`tstorish`) - Storage library for tstore/sstore operations
- **ERC2470** (`erc2470-libs`) - Singleton deployment pattern for deterministic addresses

### Testing Structure
Tests mirror the source structure with unit tests for libraries and integration tests for main contracts. Mock contracts in `test/mocks/` simulate external protocol interactions.

### Deployment Pattern
Uses singleton deployment via ERC2470 for deterministic addresses across chains. Deployment scripts handle environment variable configuration and verification automatically.