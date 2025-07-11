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
        inferredRelayData = new TrailsRelayDecoder.DecodedRelayData[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            inferredRelayData[i] = TrailsRelayDecoder.decodeRelayCalldataForSapient(calls[i]);
        }
    }
}
