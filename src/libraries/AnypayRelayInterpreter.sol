// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {RelayFacet} from "lifi-contracts/Facets/RelayFacet.sol";
import {AnypayRelayInfo} from "@/interfaces/AnypayRelay.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";

/**
 * @title AnypayRelayInterpreter
 * @author Shun Kakinoki
 * @notice Library for interpreting Relay data into AnypayRelayInfo structs.
 */
library AnypayRelayInterpreter {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when the lengths of attested and inferred Relay info arrays do not match.
    error MismatchedRelayInfoLengths();
    /// @notice Thrown when an inferred Relay info has a zero minimum amount.
    error InvalidInferredMinAmount();
    /// @notice Thrown when an attested Relay info cannot find a unique, matching inferred Relay info.
    /// @param destinationChainId The destination chain ID of the attested info.
    /// @param sendingAssetId The sending asset ID of the attested info.
    error NoMatchingInferredInfoFound(uint256 destinationChainId, address sendingAssetId);
    /// @notice Thrown when an inferred Relay info's inferred amount is larger than its matched attested one.
    /// @param inferredAmount The amount from the inferred Relay info.
    /// @param attestedAmount The amount from the attested Relay info.
    error InferredAmountTooHigh(uint256 inferredAmount, uint256 attestedAmount);

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    function getOriginInfo(ILiFi.BridgeData memory bridgeData, RelayFacet.RelayData memory relayData)
        internal
        view
        returns (AnypayRelayInfo memory)
    {
        return AnypayRelayInfo({
            requestId: relayData.requestId,
            signature: relayData.signature,
            nonEVMReceiver: relayData.nonEVMReceiver,
            receivingAssetId: relayData.receivingAssetId,
            sendingAssetId: bridgeData.sendingAssetId,
            receiver: bridgeData.receiver,
            destinationChainId: bridgeData.destinationChainId,
            minAmount: bridgeData.minAmount,
            target: address(this)
        });
    }

    /**
     * @notice Validates that each attested AnypayRelayInfo struct matches a unique, valid inferred AnypayRelayInfo struct.
     * @dev This function ensures:
     *      1. Array Lengths: `inferredRelayInfos` and `attestedRelayInfos` must have the same length.
     *      2. Inferred Info Validity: All `inferredRelayInfos` must have a non-zero minimum amount.
     *      3. Unique Match: Each `attestedRelayInfos[i]` must find a unique `inferredRelayInfos[j]` matching on `destinationChainId` and `sendingAssetId`.
     *      4. Minimum Amount Check: For matched pairs, `inferred.minAmount` must not be greater than `attested.minAmount`.
     *      Reverts with specific errors upon validation failure.
     * @param inferredRelayInfos Array of AnypayRelayInfo structs inferred from current transaction data.
     * @param attestedRelayInfos Array of AnypayRelayInfo structs derived from attestations (these are the reference).
     */
    function validateRelayInfos(
        AnypayRelayInfo[] memory inferredRelayInfos,
        AnypayRelayInfo[] memory attestedRelayInfos
    ) internal pure returns (bool) {
        if (inferredRelayInfos.length != attestedRelayInfos.length) {
            revert MismatchedRelayInfoLengths();
        }

        uint256 numInfos = attestedRelayInfos.length;
        if (numInfos == 0) {
            return false;
        }

        // Validate all inferredRelayInfos upfront
        for (uint256 i = 0; i < numInfos; i++) {
            if (inferredRelayInfos[i].minAmount == 0) {
                revert InvalidInferredMinAmount();
            }
        }

        bool[] memory inferredInfoUsed = new bool[](numInfos);

        // For each attestedRelayInfo, find a unique, matching, and valid inferredRelayInfo
        for (uint256 i = 0; i < numInfos; i++) {
            AnypayRelayInfo memory currentAttestedInfo = attestedRelayInfos[i];

            bool foundMatch = false;
            for (uint256 j = 0; j < numInfos; j++) {
                if (inferredInfoUsed[j]) {
                    continue;
                }

                AnypayRelayInfo memory currentInferredInfo = inferredRelayInfos[j];

                if (
                    currentAttestedInfo.destinationChainId == currentInferredInfo.destinationChainId
                        && currentAttestedInfo.sendingAssetId == currentInferredInfo.sendingAssetId
                ) {
                    if (currentInferredInfo.minAmount > currentAttestedInfo.minAmount) {
                        revert InferredAmountTooHigh(currentInferredInfo.minAmount, currentAttestedInfo.minAmount);
                    }
                    inferredInfoUsed[j] = true;
                    foundMatch = true;
                    break;
                }
            }

            if (!foundMatch) {
                revert NoMatchingInferredInfoFound(
                    currentAttestedInfo.destinationChainId, currentAttestedInfo.sendingAssetId
                );
            }
        }

        return true;
    }
}
