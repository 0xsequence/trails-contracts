# Deploying TrailsLiFiSapientSigner

This guide explains how to deploy the `TrailsLiFiSapientSigner` contract using Foundry's `forge script`.

## Prerequisites

Before running the deployment script, you need to set the following environment variables:

*   `PRIVATE_KEY`: The private key of the account you want to deploy from.
*   `RPC_URL`: The RPC URL of the network you want to deploy to (e.g., Sepolia, Mainnet).
*   `ETHERSCAN_API_KEY`: Your Etherscan API key for contract verification.

You can set them in your shell like this:

```bash
export PRIVATE_KEY="your_private_key_here"
export RPC_URL="your_rpc_url_here"
export ETHERSCAN_API_KEY="your_etherscan_api_key_here"
```

## Using .envrc for Automatic Environment Variable Loading

To avoid manually exporting the environment variables every time you open a new terminal session in this directory, you can use a tool like [direnv](https://direnv.net/). `direnv` allows you to load environment variables automatically when you `cd` into a directory containing a `.envrc` file.

**1. Install direnv:**

Follow the installation instructions for your operating system on the [official direnv website](https://direnv.net/docs/installation.html).

**2. Create a `.envrc` file:**

Create a file named `.envrc` in the root of your `trails-contracts` project (or the directory from which you run the forge commands) with the following content:

```bash
export RPC_URL="your_rpc_url_here"
export ETHERSCAN_API_KEY="your_etherscan_api_key_here"
```

**Important:** Make sure to add `.envrc` to your `.gitignore` file to prevent accidentally committing your private keys or other sensitive information.

```
.envrc
```

**3. Allow direnv to load the file:**

Navigate to the directory containing your `.envrc` file in your terminal and run:

```bash
direnv allow
```

Now, whenever you `cd` into this directory, `direnv` will automatically load the environment variables defined in your `.envrc` file. When you `cd` out of the directory, `direnv` will unload them.

## Deployment Command

Once the environment variables are set, you can deploy the contract using the following command:

```bash
forge script script/TrailsLiFiSapientSigner.s.sol:Deploy --sig "run()" \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --chain $CHAIN_ID \
    --verifier-url $VERIFIER_URL \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --sender $ADDRESS \
    --via-ir \
    -vvvv
```

```bash
forge script script/TrailsRelaySapientSigner.s.sol:Deploy --sig "run()" \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --chain $CHAIN_ID \
    --verifier-url $VERIFIER_URL \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --sender $ADDRESS \
    --via-ir \
    -vvvv
```

```bash
forge script script/TrailsCCTPV2SapientSigner.s.sol:Deploy --sig "run()" \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --chain $CHAIN_ID \
    --verifier-url $VERIFIER_URL \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --sender $ADDRESS \
    --via-ir \
    -vvvv
```

```bash
forge script script/TrailsMulticall3Router.s.sol:Deploy --sig "run()" \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --chain $CHAIN_ID \
    --verifier-url $VERIFIER_URL \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --sender $ADDRESS \
    --via-ir \
    -vvvv
```

**Explanation of flags:**
*   `script/TrailsLiFiSapientSigner.s.sol:Deploy`: Specifies the script file and the contract within that file to run.
*   `--sig "run()"`: Specifies the function signature to execute in the script contract.
*   `--rpc-url $RPC_URL`: Specifies the RPC endpoint of the target blockchain.
*   `--broadcast`: Broadcasts the transactions to the network.
*   `--verify`: Verifies the deployed contract on Etherscan.
*   `--etherscan-api-key $ETHERSCAN_API_KEY`: Provides the API key for Etherscan verification.
*   `--sender $ADDRESS`: Specifies the address from which to deploy the contract (should match the private key in `PRIVATE_KEY`).
*   `-vvvv`: Sets the verbosity level for detailed output.

## References

For more information on `forge script` and its capabilities, refer to the official Foundry Book documentation:
[https://book.getfoundry.sh/reference/forge/forge-script](https://book.getfoundry.sh/reference/forge/forge-script)

## Verifying an Already Deployed Contract

If you have already deployed the `TrailsLiFiSapientSigner` contract and want to verify it separately, you can use the `forge verify-contract` command.

**Prerequisites:**

Ensure the following environment variables are set, or provide them as command-line arguments:

*   `ETHERSCAN_API_KEY`: Your Etherscan API key.
*   `RPC_URL`: The RPC URL of the network where the contract is deployed (used to fetch constructor arguments if not provided directly, and to determine chain ID if not specified).
    Alternatively, you can use the `--chain <CHAIN_ID>` flag.

**Verification Command:**

```bash
forge verify-contract 0x9a013e7d186611af36a918ef23d81886e8c256f8 src/TrailsRelaySapientSigner.sol:TrailsRelaySapientSigner \
    --chain $CHAIN_ID \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --verifier-url $VERIFIER_URL \
    --compiler-version 0.8.30 \
    --watch
```

```bash
forge verify-contract 0x099E30e44A3fD4EdAb23D678a08cDE2dA2f2FF10 src/TrailsMulticall3Router.sol:TrailsMulticall3Router \
    --chain $CHAIN_ID \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --verifier-url $VERIFIER_URL \
    --compiler-version 0.8.30 \
    --watch
```

**Explanation of flags:**

*   `<DEPLOYED_CONTRACT_ADDRESS>`: The address of the `TrailsLiFiSapientSigner` contract on the blockchain.
*   `src/TrailsLiFiSapientSigner.sol:TrailsLiFiSapientSigner`: The path to the source file and the contract name.
*   `--chain <CHAIN_ID>`: The chain ID of the network (e.g., `1` for Ethereum Mainnet, `11155111` for Sepolia). You can often omit this if your `RPC_URL` points to the correct network.
*   `--etherscan-api-key $ETHERSCAN_API_KEY`: Your Etherscan API key.
*   `--constructor-args $(cast abi-encode "constructor(address)" "<LIFI_DIAMOND_ADDRESS>")`: The ABI-encoded constructor arguments. The `TrailsLiFiSapientSigner` constructor takes one argument: `address _lifiDiamondAddress`.
    *   Replace `<LIFI_DIAMOND_ADDRESS>` with the actual LiFi Diamond address that was used when the contract was deployed.
*   `--compiler-version <YOUR_SOLC_VERSION>`: The Solidity compiler version used to compile your contract (e.g., `0.8.17`). You might need to specify the full version string (e.g., `v0.8.17+commit.8df45f5f`).
*   `--num-of-optimizations <OPTIMIZER_RUNS>`: The number of optimizer runs used during compilation. If you didn't specify this during compilation, it might be the default (e.g., `200`). Check your `foundry.toml` or compilation output.
*   `--watch`: Waits for the verification result from Etherscan.
*   `--via-ir`: Include this flag if your `foundry.toml` has `viaIR = true` or if you used this flag during the initial deployment.

**Important Notes:**

*   **Compiler Version and Optimizer Runs:** Getting the exact compiler version and number of optimizer runs correct is crucial for successful verification. If verification fails, these are common culprits. You can often find this information in your `foundry.toml` or the compilation artifacts (e.g., in the `out/` directory).
*   **LiFi Diamond Address:** Ensure the `<LIFI_DIAMOND_ADDRESS>` in the `--constructor-args` matches the one used when the specific contract instance was deployed.

*   **Error: No matching artifact found:** If you encounter an error like `Error: No matching artifact found for TrailsLiFiSapientSigner`, it means Foundry cannot locate the compiled contract artifact. 
    1.  Ensure you are running the command from the project root directory.
    2.  Run `forge build` in your project root to compile your contracts and generate the necessary artifacts. 
    3.  If the issue persists, try forcefully recompiling with `forge build --force` or cleaning and rebuilding with `forge clean && forge build`.

For more details, refer to the [Foundry Book - `forge verify-contract`](https://book.getfoundry.sh/reference/forge/forge-verify-contract).
