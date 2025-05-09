// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

/**
 * @title AnypayIntentParams
 * @author Shun Kakinoki
 * @notice Library for handling Anypay intent parameters, specifically for hashing.
 */
library AnypayIntentParams {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error UserAddressIsZero();
    error OriginTokensIsEmpty();
    error DestinationCallsIsEmpty();
    error DestinationTokensIsEmpty();
    error InvalidDestinationCallKind();
    error InvalidCallInDestination();

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    /**
     * @dev Represents an origin token with an address and chain ID.
     * Zero address for tokenAddress can represent the native token of the chain.
     */
    struct OriginToken {
        address tokenAddress;
        uint64 chainId;
    }

    /**
     * @dev Represents a destination token with an address, chain ID, and amount.
     * Zero address for tokenAddress can represent the native token of the chain.
     */
    struct DestinationToken {
        address tokenAddress;
        uint64 chainId;
        uint256 amount;
    }

    /**
     * @dev Represents the parameters for an Anypay intent.
     * Each item in destinationCalls is expected to be a Payload.Decoded struct
     * with kind = Payload.KIND_TRANSACTIONS, containing the actual calls.
     */
    struct IntentParamsData {
        address userAddress;
        OriginToken[] originTokens;
        Payload.Decoded[] destinationCalls;
        DestinationToken[] destinationTokens;
    }

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Generates a unique bytes32 hash from the IntentParamsData struct.
     * @dev The hashing mechanism ABI-encodes the parameters in a specific order
     *      (userAddress, originTokens, destinationCalls, destinationTokens)
     *      and then applies keccak256.
     *      It includes validation checks for required fields.
     * @param params The intent parameters to hash.
     * @return intentHash The keccak256 hash of the ABI-encoded parameters.
     */
    function hashIntentParams(IntentParamsData memory params) internal view returns (bytes32 intentHash) {
        if (params.userAddress == address(0)) revert UserAddressIsZero();
        if (params.originTokens.length == 0) revert OriginTokensIsEmpty();
        if (params.destinationCalls.length == 0) revert DestinationCallsIsEmpty();
        if (params.destinationTokens.length == 0) revert DestinationTokensIsEmpty();

        // Temporary hash for accumulating destination call hashes
        bytes32 cumulativeCallsHash = bytes32(0);

        for (uint256 i = 0; i < params.destinationCalls.length; i++) {
            Payload.Decoded memory currentDestCallPayload = params.destinationCalls[i];
            // Check each destination call payload is of KIND_TRANSACTIONS
            if (currentDestCallPayload.kind != Payload.KIND_TRANSACTIONS) {
                revert InvalidDestinationCallKind();
            }
            // Ensure there are actual calls within this KIND_TRANSACTIONS payload
            if (currentDestCallPayload.calls.length == 0) {
                revert InvalidCallInDestination();
            }

            // The Payload.hash function expects a single Decoded struct.
            // It internally handles hashing based on the 'kind'.
            // For KIND_TRANSACTIONS, it will hash the .calls array according to EIP-712 logic.
            cumulativeCallsHash = keccak256(abi.encodePacked(cumulativeCallsHash, Payload.hash(currentDestCallPayload)));
        }

        // ABI encode the parameters in the specified order.
        // The `params.destinationCalls` itself (an array of structs) is encoded.
        // The `cumulativeCallsHash` is also included to ensure the integrity of the call data.
        bytes memory encodedData = abi.encode(
            params.userAddress,
            params.originTokens,
            params.destinationCalls,
            params.destinationTokens,
            cumulativeCallsHash
        );

        intentHash = keccak256(encodedData);
    }
}
