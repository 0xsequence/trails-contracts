// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {AnypayRelayInfo} from "@/interfaces/AnypayRelay.sol";

/**
 * @title AnypayRelayParams
 * @author Shun Kakinoki
 * @notice Library for handling Anypay Relay intent parameters, specifically for hashing.
 */
library AnypayRelayParams {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error UserAddressIsZero();
    error OriginTokensIsEmpty();
    error DestinationCallsIsEmpty();
    error DestinationTokensIsEmpty();
    error InvalidDestinationCallKind();
    error InvalidCallInDestination();
    error RelayInfosIsEmpty();
    error AttestationAddressIsZero();

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
        uint256 nonce;
        OriginToken[] originTokens;
        Payload.Decoded[] destinationCalls;
        DestinationToken[] destinationTokens;
    }

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Generates a unique bytes32 hash for an array of AnypayRelayInfo.
     * @param relayInfos An array of Relay-specific information for the transaction.
     * @param attestationAddress The address used for attestation.
     * @return The keccak256 hash of the Relay information.
     */
    function getAnypayRelayInfoHash(AnypayRelayInfo[] memory relayInfos, address attestationAddress)
        public
        pure
        returns (bytes32)
    {
        if (relayInfos.length == 0) revert RelayInfosIsEmpty();
        if (attestationAddress == address(0)) revert AttestationAddressIsZero();
        return keccak256(abi.encode(relayInfos, attestationAddress));
    }

    /**
     * @notice Generates a unique bytes32 hash for a Relay intent.
     * @dev This function combines the hash of general intent parameters with the hash of Relay-specific information.
     *      It performs validation checks on all critical fields.
     * @param intentParams The general intent parameters.
     * @param relayInfos An array of Relay-specific information for the transaction.
     * @param attestationAddress The address used for attestation.
     * @return intentHash The final keccak256 hash of the combined Relay intent data.
     */
    function hashRelayIntent(
        IntentParamsData memory intentParams,
        AnypayRelayInfo[] memory relayInfos,
        address attestationAddress
    ) internal view returns (bytes32) {
        if (intentParams.userAddress == address(0)) revert UserAddressIsZero();
        if (intentParams.originTokens.length == 0) revert OriginTokensIsEmpty();
        if (intentParams.destinationCalls.length == 0) revert DestinationCallsIsEmpty();
        if (intentParams.destinationTokens.length == 0) revert DestinationTokensIsEmpty();

        bytes32 cumulativeCallsHash = bytes32(0);

        for (uint256 i = 0; i < intentParams.destinationCalls.length; i++) {
            Payload.Decoded memory currentDestCallPayload = intentParams.destinationCalls[i];
            if (currentDestCallPayload.kind != Payload.KIND_TRANSACTIONS) {
                revert InvalidDestinationCallKind();
            }
            if (currentDestCallPayload.calls.length == 0) {
                revert InvalidCallInDestination();
            }
            cumulativeCallsHash =
                keccak256(abi.encodePacked(cumulativeCallsHash, Payload.hashFor(currentDestCallPayload, address(0))));
        }

        bytes memory encodedData = abi.encode(
            intentParams.userAddress,
            intentParams.nonce,
            intentParams.originTokens,
            intentParams.destinationTokens,
            cumulativeCallsHash
        );
        bytes32 intentParamsHash = keccak256(encodedData);

        bytes32 relayInfoHash = getAnypayRelayInfoHash(relayInfos, attestationAddress);

        return keccak256(abi.encodePacked(intentParamsHash, relayInfoHash));
    }
} 