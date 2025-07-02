// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {ECDSA} from "solady/utils/ECDSA.sol";
import {AnypayRelayInfo} from "@/interfaces/AnypayRelay.sol";
import {AnypayRelayDecoder} from "@/libraries/AnypayRelayDecoder.sol";
import {AnypayRelayConstants} from "@/libraries/AnypayRelayConstants.sol";
import {AnypayRelayInterpreter} from "@/libraries/AnypayRelayInterpreter.sol";
import {AnypayExecutionInfo} from "@/interfaces/AnypayExecutionInfo.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {console} from "forge-std/console.sol";

/**
 * @title AnypayRelayValidator
 * @author Shun Kakinoki
 * @notice Library for validating Anypay Relay data.
 */
library AnypayRelayValidator {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------

    using ECDSA for bytes32;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error InvalidAttestation();
    error InvalidRelayQuote();
    error MismatchedRelayInfoLengths();
    error InvalidInferredMinAmount();
    error NoMatchingInferredInfoFound(uint256 destinationChainId, address originToken);
    error InferredAmountTooHigh(uint256 inferredAmount, uint256 attestedAmount);

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Validates if the recipient of a relay call is the designated relay solver.
     * @dev This function decodes the relay calldata from a `Payload.Call` struct to determine
     *      the ultimate receiver of the assets (either native or ERC20) and checks if it
     *      matches the provided `relaySolver` address.
     * @param call The `Payload.Call` struct representing a single transaction in the payload.
     * @return True if the recipient is the `relaySolver`, false otherwise.
     */
    function isValidRelayRecipient(Payload.Call memory call) internal pure returns (bool) {
        AnypayRelayDecoder.DecodedRelayData memory decodedData = AnypayRelayDecoder.decodeRelayCalldataForSapient(call);
        return decodedData.receiver == AnypayRelayConstants.RELAY_SOLVER
            || decodedData.receiver == AnypayRelayConstants.RELAY_APPROVAL_PROXY
            || decodedData.receiver == AnypayRelayConstants.RELAY_APPROVAL_PROXY_V2
            || decodedData.receiver == AnypayRelayConstants.RELAY_RECEIVER;
    }

    /**
     * @notice Validates an array of relay calls to ensure all are sent to the relay solver.
     * @dev Iterates through an array of `Payload.Call` structs and uses `isValidRelayRecipient`
     *      to verify each one. The function returns false if the array is empty.
     * @param calls The array of `Payload.Call` structs to validate.
     * @return True if all calls are to the `relaySolver`, false otherwise.
     */
    function areValidRelayRecipients(Payload.Call[] memory calls) internal pure returns (bool) {
        if (calls.length == 0) {
            return false;
        }
        for (uint256 i = 0; i < calls.length; i++) {
            if (!isValidRelayRecipient(calls[i])) {
                return false;
            }
        }
        return true;
    }

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
