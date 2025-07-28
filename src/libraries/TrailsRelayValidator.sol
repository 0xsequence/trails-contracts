// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {ECDSA} from "solady/utils/ECDSA.sol";
import {TrailsRelayInfo} from "@/interfaces/TrailsRelay.sol";
import {TrailsRelayDecoder} from "@/libraries/TrailsRelayDecoder.sol";
import {TrailsRelayConstants} from "@/libraries/TrailsRelayConstants.sol";
import {TrailsRelayInterpreter} from "@/libraries/TrailsRelayInterpreter.sol";
import {TrailsExecutionInfo} from "@/interfaces/TrailsExecutionInfo.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {console} from "forge-std/console.sol";

/**
 * @title TrailsRelayValidator
 * @author Shun Kakinoki
 * @notice Library for validating Trails Relay data.
 */
library TrailsRelayValidator {
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

    function validate(bytes calldata data) internal pure {
        bytes memory dataAsMemory = data;
        require(areValidRelayRecipients(dataAsMemory), "Invalid relay recipients");
    }

    /**
     * @notice Validates if the recipient of a relay call is the designated relay solver.
     * @dev This function decodes the relay calldata from a `Payload.Call` struct to determine
     *      the ultimate receiver of the assets (either native or ERC20) and checks if it
     *      matches the provided `relaySolver` address.
     * @param call The `Payload.Call` struct representing a single transaction in the payload.
     * @return True if the recipient is the `relaySolver`, false otherwise.
     */
    function isValidRelayRecipient(Payload.Call memory call) private pure returns (bool) {
        TrailsRelayDecoder.DecodedRelayData memory decodedData = TrailsRelayDecoder.decodeRelayCalldataForSapient(call);
        return decodedData.receiver == TrailsRelayConstants.RELAY_SOLVER
            || decodedData.receiver == TrailsRelayConstants.RELAY_APPROVAL_PROXY
            || decodedData.receiver == TrailsRelayConstants.RELAY_APPROVAL_PROXY_V2
            || decodedData.receiver == TrailsRelayConstants.RELAY_RECEIVER
            || decodedData.receiver == TrailsRelayConstants.RELAY_MULTICALL_PROXY;
    }

    /**
     * @notice Validates an array of relay calls to ensure all are sent to the relay solver.
     * @dev Iterates through an array of `Payload.Call` structs and uses `isValidRelayRecipient`
     *      to verify each one. The function returns false if the array is empty.
     * @param data The abi-encoded array of `Payload.Call` structs to validate.
     * @return True if all calls are to the `relaySolver`, false otherwise.
     */
    function areValidRelayRecipients(bytes memory data) internal pure returns (bool) {
        Payload.Call[] memory calls = abi.decode(data, (Payload.Call[]));
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
     * @notice Validates that each attested TrailsExecutionInfo struct matches a unique, valid DecodedRelayData struct.
     * @dev This function ensures:
     *      1. Array Lengths: `inferredRelayData` and `attestedExecutionInfos` must have the same length.
     *      2. Inferred Info Validity: All `inferredRelayData` must have a non-zero amount.
     *      3. Unique Match: Each `attestedExecutionInfos[i]` must find a unique `inferredRelayData[j]` matching on `originToken`.
     *      4. Amount Check: For matched pairs, `inferred.amount` must not be greater than `attested.amount`.
     *      Reverts with specific errors upon validation failure.
     * @param inferredRelayData Array of DecodedRelayData structs inferred from current transaction data.
     * @param attestedExecutionInfos Array of TrailsExecutionInfo structs derived from attestations (these are the reference).
     */
    function validateRelayInfos(
        TrailsRelayDecoder.DecodedRelayData[] memory inferredRelayData,
        TrailsExecutionInfo[] memory attestedExecutionInfos
    ) internal view returns (bool) {
        uint256 numAttestedInfos = attestedExecutionInfos.length;
        if (numAttestedInfos == 0) {
            return true;
        }

        uint256 numInferredInfos = inferredRelayData.length;
        if (numInferredInfos != numAttestedInfos) {
            revert MismatchedRelayInfoLengths();
        }

        bool[] memory inferredInfoUsed = new bool[](numInferredInfos);

        for (uint256 i = 0; i < numAttestedInfos; i++) {
            TrailsExecutionInfo memory currentAttestedInfo = attestedExecutionInfos[i];

            if (currentAttestedInfo.originChainId != block.chainid) {
                continue;
            }

            bool foundMatch = false;
            for (uint256 j = 0; j < numInferredInfos; j++) {
                if (inferredInfoUsed[j]) {
                    continue;
                }

                TrailsRelayDecoder.DecodedRelayData memory currentInferredInfo = inferredRelayData[j];

                address inferredToken = currentInferredInfo.token;

                if (currentAttestedInfo.originToken == inferredToken) {
                    if (currentInferredInfo.amount == 0) {
                        revert InvalidInferredMinAmount();
                    }
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
