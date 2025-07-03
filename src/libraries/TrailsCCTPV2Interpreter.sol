// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {CCTPExecutionInfo} from "../interfaces/TrailsCCTPV2.sol";
import {TrailsCCTPV2Decoder} from "./TrailsCCTPV2Decoder.sol";

/**
 * @title TrailsCCTPV2Interpreter
 * @author Shun Kakinoki
 * @notice Library for interpreting CCTP data into CCTPExecutionInfo structs.
 */
library TrailsCCTPV2Interpreter {
    /**
     * @notice Extracts CCTP execution data from payload calls.
     * @param calls The array of `Payload.Call` structs to decode.
     * @return inferredExecutionInfos Array of decoded CCTP execution info.
     */
    function getInferredCCTPExecutionInfos(Payload.Call[] memory calls)
        internal
        pure
        returns (CCTPExecutionInfo[] memory inferredExecutionInfos)
    {
        inferredExecutionInfos = new CCTPExecutionInfo[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            inferredExecutionInfos[i] = TrailsCCTPV2Decoder.decodeCCTPData(calls[i].data);
        }
    }
} 