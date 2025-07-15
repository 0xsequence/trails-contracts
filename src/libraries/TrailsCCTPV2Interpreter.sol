// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {CCTPExecutionInfo} from "../interfaces/TrailsCCTPV2.sol";
import {TrailsExecutionInfo} from "@/interfaces/TrailsExecutionInfo.sol";
import {TrailsCCTPV2Decoder} from "./TrailsCCTPV2Decoder.sol";
import {TrailsCCTPUtils} from "./TrailsCCTPUtils.sol";

/**
 * @title TrailsCCTPV2Interpreter
 * @author Shun Kakinoki
 * @notice Library for interpreting CCTP data into TrailsExecutionInfo structs.
 */
library TrailsCCTPV2Interpreter {
    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Extracts CCTP execution data from payload calls.
     * @param calls The array of `Payload.Call` structs to decode.
     * @return inferredExecutionInfos Array of decoded CCTP execution info.
     */
    function getInferredCCTPExecutionInfos(Payload.Call[] memory calls)
        internal
        view
        returns (TrailsExecutionInfo[] memory inferredExecutionInfos)
    {
        inferredExecutionInfos = new TrailsExecutionInfo[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            CCTPExecutionInfo memory cctpInfo = TrailsCCTPV2Decoder.decodeCCTPData(calls[i].data);
            inferredExecutionInfos[i] = TrailsExecutionInfo({
                originToken: cctpInfo.burnToken,
                amount: cctpInfo.amount,
                originChainId: block.chainid,
                destinationChainId: TrailsCCTPUtils.cctpDomainToChainId(cctpInfo.destinationDomain)
            });
        }
    }
}
