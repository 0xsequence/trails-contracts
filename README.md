# Trails Contracts

Smart contracts for cross-chain payment and bridging functionality through LiFi and relay protocols, featuring **Sapient Signer modules** for Sequence v3 wallets.

## 🚀 TrailsEntrypointV2 - Revolutionary 1-Click Transactions

The latest addition to the Trails ecosystem: **TrailsEntrypointV2** enables true 1-click crypto transactions by accepting intents through ETH/ERC20 transfers with calldata suffixes, eliminating the traditional approve step.

### Key Features
- **Single Entrypoint**: All intents flow through one contract
- **Transfer Suffix Pattern**: ETH/ERC20 transfers carry intent hash in calldata
- **Commit-Prove Pattern**: Two-phase validation without approve step
- **Generic Execution**: Arbitrary multicall support for bridges/swaps

📖 **[Complete Technical Specification →](docs/TrailsEntrypointV2.md)**

## Architecture Overview

This is a Solidity project implementing **Sapient Signer modules** for Sequence v3 wallets, focusing on cross-chain payment and bridging functionality through LiFi and relay protocols.

### Primary Contracts
- **TrailsEntrypointV2** (`src/TrailsEntrypointV2.sol`) - Revolutionary single entrypoint for 1-click transactions
- **TrailsLiFiSapientSigner** (`src/TrailsLiFiSapientSigner.sol`) - Validates LiFi protocol operations via off-chain attestations
- **TrailsRelaySapientSigner** (`src/TrailsRelaySapientSigner.sol`) - Validates relay operations through attestation mechanism
- **TrailsTokenSweeper** (`src/TrailsTokenSweeper.sol`) - Utility contract for token recovery operations

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

- [TrailsEntrypointV2 Technical Specification](docs/TrailsEntrypointV2.md)
- [Foundry Book](https://book.getfoundry.sh/)

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
