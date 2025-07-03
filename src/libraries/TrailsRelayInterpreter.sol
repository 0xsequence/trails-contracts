// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {TrailsExecutionInfo} from "@/interfaces/TrailsExecutionInfo.sol";
import {TrailsRelayDecoder} from "@/libraries/TrailsRelayDecoder.sol";

/**
 * @title TrailsRelayInterpreter
 * @author Shun Kakinoki
 * @notice Library for interpreting Relay data into TrailsRelayInfo structs.
 */
library TrailsRelayInterpreter {
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
     * @notice Extracts relay data from relay calls, filtering out approval calls.
     * @dev Decodes all calls, filters out approval calls (requestId == bytes32(0)),
     *      and returns relay data for actual relay calls only.
     * @param calls The array of `Payload.Call` structs to decode.
     * @return inferredRelayData Array of decoded relay data from actual relay calls.
     */
    function getInferredRelayDatafromRelayCalls(Payload.Call[] memory calls)
        internal
        pure
        returns (TrailsRelayDecoder.DecodedRelayData[] memory inferredRelayData)
    {
        if (calls.length == 0) {
            return new TrailsRelayDecoder.DecodedRelayData[](0);
        }

        // Decode all relay calls
        TrailsRelayDecoder.DecodedRelayData[] memory allInferredRelayData =
            new TrailsRelayDecoder.DecodedRelayData[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            allInferredRelayData[i] = TrailsRelayDecoder.decodeRelayCalldataForSapient(calls[i]);
        }

        // Filter out approval calls (requestId == bytes32(0))
        uint256 actualRelayCallCount = 0;
        for (uint256 i = 0; i < allInferredRelayData.length; i++) {
            if (allInferredRelayData[i].requestId != bytes32(0)) {
                actualRelayCallCount++;
            }
        }

        // Create array containing only actual relay calls
        inferredRelayData = new TrailsRelayDecoder.DecodedRelayData[](actualRelayCallCount);
        uint256 actualIndex = 0;
        for (uint256 i = 0; i < allInferredRelayData.length; i++) {
            if (allInferredRelayData[i].requestId != bytes32(0)) {
                inferredRelayData[actualIndex] = allInferredRelayData[i];
                actualIndex++;
            }
        }
    }
}
