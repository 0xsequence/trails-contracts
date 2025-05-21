# Deploying AnypayLifiSapientSigner

This guide explains how to deploy the `AnypayLifiSapientSigner` contract using Foundry's `forge script`.

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

Create a file named `.envrc` in the root of your `anypay-contracts` project (or the directory from which you run the forge commands) with the following content:

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
forge script script/AnypayLifiSapientSigner.s.sol:Deploy --sig "run()" \
    --rpc-url $RPC_URL \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY \
    --sender $ADDRESS \
    -vvvv
```

**Explanation of flags:**
*   `script/AnypayLifiSapientSigner.s.sol:Deploy`: Specifies the script file and the contract within that file to run.
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
