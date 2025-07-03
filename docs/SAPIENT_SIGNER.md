# TrailsLiFiSapientSigner Module

## 1. Overview

The `TrailsLiFiSapientSigner` is a specialized SapientSigner module designed for Sequence v3 wallets. Its primary purpose is to facilitate LiFi protocol actions, such as swaps and bridges, by validating off-chain attestations. This mechanism allows relayers or users to execute LiFi operations based on user-attested parameters. Crucially, it enables these actions without requiring direct pre-approval (e.g., `approve` calls) on the LiFi contracts for each transaction, streamlining the user experience.

Authorization is achieved by the module computing a unique hash representing the LiFi intent and the attesting user. This computed hash is then validated against a pre-configured hash within the Sequence wallet's Sapient Signer Leaf corresponding to this module.

## 2. Integration with Sequence Wallet Configuration

The `TrailsLiFiSapientSigner` is integrated into a Sequence wallet as a "Sapient Signer Leaf" within the wallet's configuration tree. For details on wallet configurations and merkle trees, refer to the `CONFIGURATIONS.md` document, specifically section `3.5 Sapient Signer Leaf`.

A Sapient Signer Leaf for the `TrailsLiFiSapientSigner` is defined by the following components:

*   **`address`**: The deployed address of the `TrailsLiFiSapientSigner` contract.
*   **`weight`**: The signing weight this module contributes to the wallet's threshold if its validation is successful.
*   **`imageHash`**: This is a critical field. For this module, the `imageHash` configured in the leaf **must be the specific `lifiIntentHash`** that this particular signer instance is authorized to approve. This `lifiIntentHash` is dynamically computed by the `TrailsLiFiSapientSigner.recoverSapientSignature` function based on the details of the LiFi operation(s) in the transaction payload and the signer of the attestation.

**Validation Process:**

When a Sequence wallet processes a transaction that utilizes this Sapient Signer Leaf, it invokes the `recoverSapientSignature` function of the `TrailsLiFiSapientSigner` contract. The `payload` of the transaction and the `encodedSignature` (which, in this context, is the user's attestation for the LiFi intent) are passed to this function.

The `TrailsLiFiSapientSigner` contract computes and returns a hash (`lifiIntentHash`). The Sequence wallet then compares this returned hash against the `imageHash` stored in that specific Sapient Signer Leaf within its own configuration. If the hashes match, the signature is considered valid for this module, and its configured `weight` is counted towards satisfying the wallet's overall signing threshold.

## 3. Contract Details

The `TrailsLiFiSapientSigner.sol` contract defines the logic for validating LiFi intents.

### 3.1. Immutables

*   **`TARGET_LIFI_DIAMOND` (address):**
    This is the immutable address of the specific LiFi Diamond contract that this instance of `TrailsLiFiSapientSigner` is authorized to interact with. All LiFi calls decoded from the transaction payload *must* target this address. This ensures the signer module only operates on the intended LiFi protocol instance. It is set during deployment in the constructor.

### 3.2. Key Function: `recoverSapientSignature`

This is the core function of the contract, implementing the `ISapient` interface.

```solidity
function recoverSapientSignature(
    Payload.Decoded calldata payload,
    bytes calldata encodedSignature
) external view returns (bytes32)
```

*   **Parameters:**
    *   `payload (Payload.Decoded calldata)`: The decoded Sequence wallet transaction payload. The `payload.calls` array within this structure is expected to contain the specific LiFi function calls (e.g., `startBridgeTokensViaLiFi` or `swapAndStartBridgeTokensViaLiFi`) intended for the `TARGET_LIFI_DIAMOND`.
    *   `encodedSignature (bytes calldata)`: The user's signature attesting to the LiFi intent. This signature is over `payload.hashFor(address(0))` and is used to recover the `attestationSigner`.

*   **Returns:**
    *   `bytes32`: The `lifiIntentHash`. This hash is a cryptographic commitment to the validated LiFi operation(s) (derived from `payload.calls`) and the `attestationSigner`.

*   **Logic Breakdown:**
    1.  **Outer Payload Validation:**
        *   Verifies that `payload.kind` is `Payload.KIND_TRANSACTIONS`. Reverts with `InvalidPayloadKind` if not.
        *   Verifies that `payload.calls` is not empty. Reverts with `InvalidCallsLength` if it is.
    2.  **Target Address Validation:**
        *   Iterates through each call in `payload.calls`.
        *   For each `call`, it checks if `call.to` is equal to `TARGET_LIFI_DIAMOND`. Reverts with `InvalidTargetAddress` if any call targets a different address.
    3.  **Attestation Signer Recovery:**
        *   Recovers the signer's address from `encodedSignature` and `payload.hashFor(address(0))` using `ECDSA.recover`. This recovered address is the `attestationSigner`.
    4.  **LiFi Data Decoding & Interpretation:**
        *   Initializes an array `lifiInfos` to store `TrailsExecutionInfo` structs, one for each call in `payload.calls`.
        *   For each `call` in `payload.calls`:
            *   It attempts to decode `ILiFi.BridgeData` and `LibSwap.SwapData[]` from `call.data` using the `TrailsLiFiFlagDecoder.decodeLiFiDataOrRevert` library function (utilizing a decoding strategy provided in the `encodedSignature`).
            *   It then uses `TrailsLiFiInterpreter.getOriginSwapInfo` to process the decoded `bridgeData` and `swapData` to extract a standardized `TrailsExecutionInfo` struct. This struct contains key details of the LiFi operation, such as sending and receiving chain IDs, tokens, amounts, and the receiver address.
    5.  **LiFi Intent Hashing:**
        *   After processing all calls and gathering their respective `TrailsExecutionInfo`, it computes a single `lifiIntentHash`. This is done by calling `TrailsLiFiInterpreter.getTrailsExecutionInfoHash` with the array of `lifiInfos` and the recovered `attestationSigner`. This hash uniquely represents the complete set of LiFi operations being authorized by this specific user attestation.

*   **Purpose of the Returned Hash:** The `lifiIntentHash` returned by this function is the crucial piece of data that the Sequence wallet compares against the `imageHash` configured in the Sapient Signer Leaf. A match signifies valid authorization.

### 3.3. Libraries Used

*   `Payload` (from `wallet-contracts-v3/modules/Payload.sol`): For handling Sequence wallet payload structures.
*   `ECDSA` (from `@openzeppelin/contracts/utils/cryptography/ECDSA.sol`): For elliptic curve digital signature recovery.
*   `ILiFi` (from `lifi-contracts/Interfaces/ILiFi.sol`): Interface for LiFi bridge data.
*   `LibSwap` (from `lifi-contracts/Libraries/LibSwap.sol`): Library for LiFi swap data.
*   `TrailsLiFiFlagDecoder` (from `./libraries/TrailsLiFiFlagDecoder.sol`): Custom library to decode LiFi call data using a flag-based strategy.
*   `TrailsLiFiInterpreter`, `TrailsExecutionInfo` (from `./libraries/TrailsLiFiInterpreter.sol`): Custom library and struct to interpret and standardize LiFi operation details.

### 3.4. Errors

*   **`InvalidTargetAddress(address expectedTarget, address actualTarget)`**: Emitted if any call within `payload.calls` targets an address different from the immutable `TARGET_LIFI_DIAMOND`.
*   **`InvalidLifiDiamondAddress()`**: Emitted by the constructor if the `_lifiDiamondAddress` provided during deployment is `address(0)`.
*   **`InvalidPayloadKind()`**: Emitted if `payload.kind` is not `Payload.KIND_TRANSACTIONS`.
*   **`InvalidCallsLength()`**: Emitted if the `payload.calls` array is empty.
*   **Specificity of `TARGET_LIFI_DIAMOND`:** The `TrailsLiFiSapientSigner` is hardcoded at deployment to a single LiFi Diamond contract instance. This is a key security feature, preventing the module from being tricked into authorizing calls to arbitrary contracts.
*   **Integrity of Decoder and Interpreter Libraries:** The correctness and security of `TrailsLiFiFlagDecoder.sol` and `TrailsLiFiInterpreter.sol` are paramount. Any vulnerabilities in these libraries could lead to misinterpretation of the LiFi call data, potentially resulting in an `lifiIntentHash` that does not accurately reflect the user's true intent or the actual operations being performed.
*   **Attestation Security:** The private key corresponding to the `attestationSigner` must be kept secure. If this key is compromised, an attacker could forge attestations and potentially authorize malicious LiFi operations if a corresponding `imageHash` is configured in a Sapient Signer Leaf.
*   **Wallet Configuration Accuracy:** Users (or systems managing their configurations) must ensure that the `imageHash` stored in a Sapient Signer Leaf accurately corresponds to the hash of the LiFi intent they genuinely wish to authorize with that specific `attestationSigner`. A mismatch will simply result in the authorization failing. Configuring a leaf with an overly broad or incorrect `imageHash` could lead to unintended authorizations. This module is designed for specific, attested intents.
*   **No Direct State Management:** The `TrailsLiFiSapientSigner` itself does not store any state regarding approvals (like nonces or usage counts). Each call to `recoverSapientSignature` is a stateless validation based on the provided payload and attestation, resulting in a hash to be checked by the Sequence wallet against its configured `imageHash`.

## 5. Security Considerations

*   **Specificity of `TARGET_LIFI_DIAMOND`:** The `TrailsLiFiSapientSigner` is hardcoded at deployment to a single LiFi Diamond contract instance. This is a key security feature, preventing the module from being tricked into authorizing calls to arbitrary contracts.
*   **Integrity of Decoder and Interpreter Libraries:** The correctness and security of `TrailsLiFiFlagDecoder.sol` and `TrailsLiFiInterpreter.sol` are paramount. Any vulnerabilities in these libraries could lead to misinterpretation of the LiFi call data, potentially resulting in an `lifiIntentHash` that does not accurately reflect the user's true intent or the actual operations being performed.
*   **Attestation Security:** The private key corresponding to the `attestationSigner` must be kept secure. If this key is compromised, an attacker could forge attestations and potentially authorize malicious LiFi operations if a corresponding `imageHash` is configured in a Sapient Signer Leaf.