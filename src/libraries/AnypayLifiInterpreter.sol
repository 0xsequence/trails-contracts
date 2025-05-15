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
 * @title AnypayLifiInterpreter
 * @author Shun Kakinoki
 * @notice Library for interpreting LiFi data into AnypayLifiInfo structs.
 */
library AnypayLifiInterpreter {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error EmptyLibSwapData();

    // --- Errors for validateLifiInfos ---
    /// @notice Thrown when the lengths of attested and inferred LiFi info arrays do not match.
    error MismatchedLifiInfoLengths();
    /// @notice Thrown when an inferred LiFi info has an invalid (zero) origin token.
    error InferredInfo_InvalidOriginToken();
    /// @notice Thrown when an inferred LiFi info has a zero minimum amount.
    error InferredInfo_ZeroMinAmount();
    /// @notice Thrown when an inferred LiFi info cannot find a unique attestation that matches
    /// @param originChainId The origin chain ID of the inferred info that failed to find a match.
    /// @param destinationChainId The destination chain ID of the inferred info.
    /// @param originToken The origin token of the inferred info.
    error NoMatchingAttestationFound(uint256 originChainId, uint256 destinationChainId, address originToken);
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
    }

    function getAnypayLifiInfoHash(AnypayLifiInfo[] memory lifiInfos, address attestationAddress)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(lifiInfos, attestationAddress));
    }

    /**
     * @notice Validates a set of inferred AnypayLifiInfo structs against a corresponding set of attested ones.
     * @dev This function ensures that each inferred LiFi info is valid and matches a unique attested LiFi info.
     *      Matching criteria: `originChainId`, `destinationChainId`, and `originToken`.
     *      Validation checks:
     *      1. Array Lengths: `inferredLifiInfos` and `attestedLifiInfos` must have the same length.
     *      2. Inferred Info Validity: Each `inferredLifiInfos[i]` must have a non-zero origin token and a non-zero minimum amount.
     *      3. Match Existence: Each `inferredLifiInfos[i]` must find a unique `attestedLifiInfos[j]` where:
     *         - `inferred.originChainId == attested.originChainId`
     *         - `inferred.destinationChainId == attested.destinationChainId`
     *         - `inferred.originToken == attested.originToken`
     *      4. Minimum Amount Check: For the matched pair, `inferred.minAmount` must be >= `attested.minAmount`.
     *      Reverts with specific errors upon validation failure.
     * @param inferredLifiInfos Array of AnypayLifiInfo structs inferred from current transaction data (e.g., LiFi bridge data).
     * @param attestedLifiInfos Array of AnypayLifiInfo structs derived from attestations.
     */
    function validateLifiInfos(
        AnypayLifiInfo[] memory inferredLifiInfos,
        AnypayLifiInfo[] memory attestedLifiInfos
    ) internal pure {
        if (inferredLifiInfos.length != attestedLifiInfos.length) {
            revert MismatchedLifiInfoLengths();
        }

        uint256 numInfos = inferredLifiInfos.length;
        if (numInfos == 0) {
            return; // Nothing to validate
        }

        bool[] memory attestationUsed = new bool[](numInfos);

        for (uint256 i = 0; i < numInfos; i++) {
            AnypayLifiInfo memory currentInferredInfo = inferredLifiInfos[i];

            // Validate the inferred info itself (Check 2)
            if (currentInferredInfo.originToken == address(0)) {
                revert InferredInfo_InvalidOriginToken();
            }
            if (currentInferredInfo.minAmount == 0) {
                revert InferredInfo_ZeroMinAmount();
            }

            bool foundMatch = false;
            for (uint256 j = 0; j < numInfos; j++) {
                if (attestationUsed[j]) {
                    continue; // This attestation has already been matched
                }

                AnypayLifiInfo memory currentAttestedInfo = attestedLifiInfos[j];

                // Check for match (Check 3 criteria)
                if (
                    currentInferredInfo.originChainId == currentAttestedInfo.originChainId &&
                    currentInferredInfo.destinationChainId == currentAttestedInfo.destinationChainId &&
                    currentInferredInfo.originToken == currentAttestedInfo.originToken
                ) {
                    // Found a potential match. Now check minAmount (Check 4).
                    if (currentInferredInfo.minAmount < currentAttestedInfo.minAmount) {
                        revert InferredMinAmountTooLow(currentInferredInfo.minAmount, currentAttestedInfo.minAmount);
                    }

                    attestationUsed[j] = true;
                    foundMatch = true;
                    break; // Move to the next inferredInfo
                }
            }

            if (!foundMatch) {
                // No unique, matching attestation found for currentInferredInfo (Check 3 failure)
                revert NoMatchingAttestationFound(
                    currentInferredInfo.originChainId,
                    currentInferredInfo.destinationChainId,
                    currentInferredInfo.originToken
                );
            }
        }
    }
}
