// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {TrailsExecutionInfo} from "@/interfaces/TrailsExecutionInfo.sol";

/**
 * @title TrailsLiFiInterpreter
 * @author Shun Kakinoki
 * @notice Library for interpreting LiFi data into TrailsExecutionInfo structs.
 */
library TrailsLiFiInterpreter {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when the LibSwap data is empty.
    error EmptyLibSwapData();

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    function getOriginSwapInfo(ILiFi.BridgeData memory bridgeData, LibSwap.SwapData[] memory swapData)
        internal
        view
        returns (TrailsExecutionInfo memory)
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

            return TrailsExecutionInfo({
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

            return TrailsExecutionInfo({
                originToken: swapData[0].sendingAssetId,
                amount: swapData[0].fromAmount,
                originChainId: block.chainid,
                destinationChainId: block.chainid
            });
        }
    }
}
