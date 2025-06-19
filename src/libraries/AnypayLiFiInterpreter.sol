// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {AnypayExecutionInfo} from "@/interfaces/AnypayExecutionInfo.sol";

/**
 * @title AnypayLiFiInterpreter
 * @author Shun Kakinoki
 * @notice Library for interpreting LiFi data into AnypayExecutionInfo structs.
 */
library AnypayLiFiInterpreter {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when the LibSwap data is empty.
    error EmptyLibSwapData();
    /// @notice Thrown when the lengths of attested and inferred LiFi info arrays do not match.
    error MismatchedLifiInfoLengths();
    /// @notice Thrown when an inferred LiFi info has a zero minimum amount.
    error InvalidInferredMinAmount();
    /// @notice Thrown when an attested LiFi info cannot find a unique, matching inferred LiFi info.
    /// @param originChainId The origin chain ID of the attested info that failed to find a match.
    /// @param destinationChainId The destination chain ID of the attested info.
    /// @param originToken The origin token of the attested info.
    error NoMatchingInferredInfoFound(uint256 originChainId, uint256 destinationChainId, address originToken);
    /// @notice Thrown when an inferred LiFi info's inferred amount is larger than its matched attested one.
    /// @param inferredAmount The amount from the inferred LiFi info.
    /// @param attestedAmount The amount from the attested LiFi info.
    error InferredAmountTooHigh(uint256 inferredAmount, uint256 attestedAmount);

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    function getOriginSwapInfo(ILiFi.BridgeData memory bridgeData, LibSwap.SwapData[] memory swapData)
        internal
        view
        returns (AnypayExecutionInfo memory)
    {
        address originToken;
        uint256 amount;

        // If the bridge data is not empty
        if (bridgeData.transactionId != bytes32(0)) {
            if (bridgeData.hasSourceSwaps) {
                if (swapData.length == 0) {
                    revert EmptyLibSwapData();
                }
                originToken = swapData[0].sendingAssetId;
                amount = swapData[0].fromAmount;
            } else {
                originToken = bridgeData.sendingAssetId;
                amount = bridgeData.minAmount;
            }

            return AnypayExecutionInfo({
                originToken: originToken,
                amount: amount,
                originChainId: block.chainid,
                destinationChainId: bridgeData.destinationChainId
            });

            // If just swap on the origin chain
        } else {
            if (swapData.length == 0) {
                revert EmptyLibSwapData();
            }

            return AnypayExecutionInfo({
                originToken: swapData[0].sendingAssetId,
                amount: swapData[0].fromAmount,
                originChainId: block.chainid,
                destinationChainId: block.chainid
            });
        }
    }
}
