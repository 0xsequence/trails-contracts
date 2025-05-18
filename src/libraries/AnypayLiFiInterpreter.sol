// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";

error EmptyLibSwapData();

struct AnypayLifiInfo {
    address originToken;
    uint256 minAmount;
    uint256 originChainId;
    uint256 destinationChainId;
}

/**
 * @title AnypayLiFiInterpreter
 * @author Shun Kakinoki
 * @notice Library for interpreting LiFi data into AnypayLifiInfo structs.
 */
library AnypayLiFiInterpreter {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when the lengths of attested and inferred LiFi info arrays do not match.
    error MismatchedLifiInfoLengths();
    /// @notice Thrown when an inferred LiFi info has a zero minimum amount.
    error InvalidInferredMinAmount();
    /// @notice Thrown when an attested LiFi info cannot find a unique, matching inferred LiFi info.
    /// @param originChainId The origin chain ID of the attested info that failed to find a match.
    /// @param destinationChainId The destination chain ID of the attested info.
    /// @param originToken The origin token of the attested info.
    error NoMatchingInferredInfoFound(uint256 originChainId, uint256 destinationChainId, address originToken);
    /// @notice Thrown when an inferred LiFi info's minimum amount is less than its matched attested one.
    /// @param inferredAmount The minimum amount from the inferred LiFi info.
    /// @param attestedAmount The minimum amount from the attested LiFi info.
    error InferredMinAmountTooLow(uint256 inferredAmount, uint256 attestedAmount);

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    function getOriginSwapInfo(ILiFi.BridgeData memory bridgeData, LibSwap.SwapData[] memory swapData)
        internal
        view
        returns (AnypayLifiInfo memory)
    {
        address originToken;
        uint256 minAmount;

        // If the bridge data is not empty
        if (bridgeData.sendingAssetId != address(0)) {
            if (bridgeData.hasSourceSwaps) {
                if (swapData.length == 0) {
                    revert EmptyLibSwapData();
                }
                originToken = swapData[0].sendingAssetId;
                minAmount = swapData[0].fromAmount;
            } else {
                originToken = bridgeData.sendingAssetId;
                minAmount = bridgeData.minAmount;
            }

            return AnypayLifiInfo({
                originToken: originToken,
                minAmount: minAmount,
                originChainId: block.chainid,
                destinationChainId: bridgeData.destinationChainId
            });

            // If just swap on the origin chain
        } else {
            if (swapData.length == 0) {
                revert EmptyLibSwapData();
            }

            return AnypayLifiInfo({
                originToken: swapData[0].sendingAssetId,
                minAmount: swapData[0].fromAmount,
                originChainId: block.chainid,
                destinationChainId: block.chainid
            });
        }
    }

    /**
     * @notice Validates that each attested AnypayLifiInfo struct matches a unique, valid inferred AnypayLifiInfo struct.
     * @dev This function ensures:
     *      1. Array Lengths: `inferredLifiInfos` and `attestedLifiInfos` must have the same length.
     *      2. Inferred Info Validity: All `inferredLifiInfos` must have a non-zero origin token and a non-zero minimum amount.
     *      3. Match for Current Chain: Each `attestedLifiInfos[i]` with `originChainId == block.chainid` must find a unique `inferredLifiInfos[j]` matching `originChainId`, `destinationChainId`, and `originToken`.
     *      4. Minimum Amount for Current Chain Matches: For such matched pairs (where `attested.originChainId == block.chainid`), `inferred.minAmount` must be >= `attested.minAmount`.
     *      Reverts with specific errors upon validation failure.
     * @param inferredLifiInfos Array of AnypayLifiInfo structs inferred from current transaction data.
     * @param attestedLifiInfos Array of AnypayLifiInfo structs derived from attestations (these are the reference).
     */
    function validateLifiInfos(AnypayLifiInfo[] memory inferredLifiInfos, AnypayLifiInfo[] memory attestedLifiInfos)
        internal
        view
    {
        if (inferredLifiInfos.length != attestedLifiInfos.length) {
            revert MismatchedLifiInfoLengths();
        }

        uint256 numInfos = attestedLifiInfos.length; // Or inferredLifiInfos.length, they are equal here
        if (numInfos == 0) {
            return;
        }

        // Validate all inferredLifiInfos upfront (Check 2 from NatSpec).
        for (uint256 i = 0; i < numInfos; i++) {
            AnypayLifiInfo memory _currentInferredInfo = inferredLifiInfos[i];
            if (_currentInferredInfo.minAmount == 0) {
                revert InvalidInferredMinAmount();
            }
        }

        bool[] memory inferredInfoUsed = new bool[](numInfos);

        // For each attestedLifiInfo, find a unique, matching, and valid inferredLifiInfo
        // Only validate if the attestation's originChainId is the current block.chainid
        for (uint256 i = 0; i < numInfos; i++) {
            AnypayLifiInfo memory currentAttestedInfo = attestedLifiInfos[i];

            if (currentAttestedInfo.originChainId != block.chainid) {
                continue;
            }

            bool foundMatch = false;
            for (uint256 j = 0; j < numInfos; j++) {
                if (inferredInfoUsed[j]) {
                    continue;
                }

                AnypayLifiInfo memory currentInferredInfo = inferredLifiInfos[j];

                if (
                    currentAttestedInfo.originChainId == currentInferredInfo.originChainId
                        && currentAttestedInfo.destinationChainId == currentInferredInfo.destinationChainId
                        && currentAttestedInfo.originToken == currentInferredInfo.originToken
                ) {
                    if (currentInferredInfo.minAmount < currentAttestedInfo.minAmount) {
                        revert InferredMinAmountTooLow(currentInferredInfo.minAmount, currentAttestedInfo.minAmount);
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
    }
}
