// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {TrailsExecutionInfo} from "@/interfaces/TrailsExecutionInfo.sol";

/**
 * @title TrailsExecutionInfoInterpreter
 * @author Shun Kakinoki
 * @notice Library for interpreting execution info data into TrailsExecutionInfo structs.
 */
library TrailsExecutionInfoInterpreter {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when the lengths of attested and inferred execution info arrays do not match.
    error MismatchedExecutionInfoLengths();
    /// @notice Thrown when an inferred execution info has a zero minimum amount.
    error InvalidInferredMinAmount();
    /// @notice Thrown when an attested execution info cannot find a unique, matching inferred execution info.
    /// @param originChainId The origin chain ID of the attested info that failed to find a match.
    /// @param destinationChainId The destination chain ID of the attested info.
    /// @param originToken The origin token of the attested info.
    error NoMatchingInferredInfoFound(uint256 originChainId, uint256 destinationChainId, address originToken);
    /// @notice Thrown when an inferred execution info's inferred amount is larger than its matched attested one.
    /// @param inferredAmount The amount from the inferred execution info.
    /// @param attestedAmount The amount from the attested execution info.
    error InferredAmountTooHigh(uint256 inferredAmount, uint256 attestedAmount);

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Validates that each attested TrailsExecutionInfo struct matches a unique, valid inferred TrailsExecutionInfo struct.
     * @dev This function ensures:
     *      1. Array Lengths: `inferredExecutionInfos` and `attestedExecutionInfos` must have the same length.
     *      2. Inferred Info Validity: All `inferredExecutionInfos` must have a non-zero origin token and a non-zero minimum amount.
     *      3. Match for Current Chain: Each `attestedExecutionInfos[i]` with `originChainId == block.chainid` must find a unique `inferredExecutionInfos[j]` matching `originChainId`, `destinationChainId`, and `originToken`.
     *      4. Minimum Amount for Current Chain Matches: For such matched pairs (where `attested.originChainId == block.chainid`), `inferred.minAmount` must be >= `attested.minAmount`.
     *      Reverts with specific errors upon validation failure.
     * @param inferredExecutionInfos Array of TrailsExecutionInfo structs inferred from current transaction data.
     * @param attestedExecutionInfos Array of TrailsExecutionInfo structs derived from attestations (these are the reference).
     */
    function validateExecutionInfos(
        TrailsExecutionInfo[] memory inferredExecutionInfos,
        TrailsExecutionInfo[] memory attestedExecutionInfos
    ) internal view returns (bool) {
        if (inferredExecutionInfos.length != attestedExecutionInfos.length) {
            revert MismatchedExecutionInfoLengths();
        }

        uint256 numInfos = attestedExecutionInfos.length;
        if (numInfos == 0) {
            return false;
        }

        // Validate all inferredExecutionInfos upfront
        for (uint256 i = 0; i < numInfos; i++) {
            TrailsExecutionInfo memory _currentInferredInfo = inferredExecutionInfos[i];
            if (_currentInferredInfo.amount == 0) {
                revert InvalidInferredMinAmount();
            }
        }

        bool[] memory inferredInfoUsed = new bool[](numInfos);

        // For each attestedExecutionInfo, find a unique, matching, and valid inferredExecutionInfo
        // Only validate if the attestation's originChainId is the current block.chainid
        for (uint256 i = 0; i < numInfos; i++) {
            TrailsExecutionInfo memory currentAttestedInfo = attestedExecutionInfos[i];

            if (currentAttestedInfo.originChainId != block.chainid) {
                continue;
            }

            bool foundMatch = false;
            for (uint256 j = 0; j < numInfos; j++) {
                if (inferredInfoUsed[j]) {
                    continue;
                }

                TrailsExecutionInfo memory currentInferredInfo = inferredExecutionInfos[j];

                if (
                    currentAttestedInfo.originChainId == currentInferredInfo.originChainId
                        && currentAttestedInfo.destinationChainId == currentInferredInfo.destinationChainId
                        && currentAttestedInfo.originToken == currentInferredInfo.originToken
                ) {
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
                    currentAttestedInfo.originChainId,
                    currentAttestedInfo.destinationChainId,
                    currentAttestedInfo.originToken
                );
            }
        }

        return true;
    }
}
