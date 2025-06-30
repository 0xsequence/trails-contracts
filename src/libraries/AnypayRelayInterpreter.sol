// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {AnypayExecutionInfo} from "@/interfaces/AnypayExecutionInfo.sol";
import {AnypayRelayDecoder} from "@/libraries/AnypayRelayDecoder.sol";

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
    /// @param originToken The sending asset ID of the attested info.
    error NoMatchingInferredInfoFound(uint256 destinationChainId, address originToken);
    /// @notice Thrown when an inferred Relay info's inferred amount is larger than its matched attested one.
    /// @param inferredAmount The amount from the inferred Relay info.
    /// @param attestedAmount The amount from the attested Relay info.
    error InferredAmountTooHigh(uint256 inferredAmount, uint256 attestedAmount);

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Validates that each attested AnypayExecutionInfo struct matches a unique, valid DecodedRelayData struct.
     * @dev This function ensures:
     *      1. Array Lengths: `inferredRelayData` and `attestedExecutionInfos` must have the same length.
     *      2. Inferred Info Validity: All `inferredRelayData` must have a non-zero amount.
     *      3. Unique Match: Each `attestedExecutionInfos[i]` must find a unique `inferredRelayData[j]` matching on `originToken`.
     *      4. Amount Check: For matched pairs, `inferred.amount` must not be greater than `attested.amount`.
     *      Reverts with specific errors upon validation failure.
     * @param inferredRelayData Array of DecodedRelayData structs inferred from current transaction data.
     * @param attestedExecutionInfos Array of AnypayExecutionInfo structs derived from attestations (these are the reference).
     */
    function validateRelayInfos(
        AnypayRelayDecoder.DecodedRelayData[] memory inferredRelayData,
        AnypayExecutionInfo[] memory attestedExecutionInfos
    ) internal view returns (bool) {
        if (inferredRelayData.length != attestedExecutionInfos.length) {
            revert MismatchedRelayInfoLengths();
        }

        uint256 numInfos = attestedExecutionInfos.length;
        if (numInfos == 0) {
            return false;
        }

        // Validate all inferredRelayData upfront
        for (uint256 i = 0; i < numInfos; i++) {
            if (inferredRelayData[i].amount == 0) {
                revert InvalidInferredMinAmount();
            }
        }

        bool[] memory inferredInfoUsed = new bool[](numInfos);

        // For each attestedExecutionInfo, find a unique, matching, and valid inferredRelayData
        for (uint256 i = 0; i < numInfos; i++) {
            AnypayExecutionInfo memory currentAttestedInfo = attestedExecutionInfos[i];

            if (currentAttestedInfo.originChainId != block.chainid) {
                continue;
            }

            bool foundMatch = false;
            for (uint256 j = 0; j < numInfos; j++) {
                if (inferredInfoUsed[j]) {
                    continue;
                }

                AnypayRelayDecoder.DecodedRelayData memory currentInferredInfo = inferredRelayData[j];

                if (currentAttestedInfo.originToken == currentInferredInfo.token) {
                    if (currentInferredInfo.amount > currentAttestedInfo.amount) {
                        revert InferredAmountTooHigh(currentInferredInfo.amount, currentAttestedInfo.amount);
                    }
                    inferredInfoUsed[j] = true;
                    foundMatch = true;
                    break;
                }
            }

            if (!foundMatch) {
                revert NoMatchingInferredInfoFound(
                    currentAttestedInfo.destinationChainId, currentAttestedInfo.originToken
                );
            }
        }

        return true;
    }
}
