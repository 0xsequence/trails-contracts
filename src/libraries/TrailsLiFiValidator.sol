// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {TrailsLiFiFlagDecoder} from "@/libraries/TrailsLiFiFlagDecoder.sol";
import {TrailsDecodingStrategy} from "@/interfaces/TrailsLiFi.sol";

/**
 * @title TrailsLiFiValidator
 * @author Shun Kakinoki
 * @notice Library for validating decoded LiFi Protocol data structures.
 *         Provides functions to check if BridgeData and SwapData are valid and not "empty".
 */
library TrailsLiFiValidator {
    error InvalidLiFiData();
    /**
     * @notice Checks if a single LibSwap.SwapData struct is valid and represents an actual swap.
     * @dev A swap is considered "not empty" if it has a target for the call, approval, or a positive amount.
     * @param swapData The SwapData struct to validate.
     * @return True if the swapData is valid and not empty, false otherwise.
     */

    function isSwapDataValid(LibSwap.SwapData memory swapData) internal pure returns (bool) {
        return swapData.callTo != address(0) || swapData.approveTo != address(0) || swapData.fromAmount > 0;
    }

    /**
     * @notice Checks if a LibSwap.SwapData array is valid and contains at least one non-empty swap.
     * @dev An array is valid if it's not empty and at least one of its elements is a valid, non-empty swap.
     * @param swapDataArray The array of SwapData structs to validate.
     * @return True if the array is valid and contains at least one non-empty swap, false otherwise.
     */
    function isSwapDataArrayValid(LibSwap.SwapData[] memory swapDataArray) internal pure returns (bool) {
        if (swapDataArray.length == 0) {
            return false;
        }
        for (uint256 i = 0; i < swapDataArray.length; i++) {
            if (isSwapDataValid(swapDataArray[i])) {
                // Found at least one valid and non-empty swap
                return true;
            }
        }
        // No valid and non-empty swap found in the array
        return false;
    }

    /**
     * @notice Checks if an ILiFi.BridgeData struct is valid and contains essential information.
     * @dev Validates key fields like transactionId, bridge identifier, asset IDs, receiver, amount, and destination chain.
     * @param bridgeData The BridgeData struct to validate.
     * @return True if the bridgeData is valid and not empty, false otherwise.
     */
    function isBridgeDataValid(ILiFi.BridgeData memory bridgeData) internal pure returns (bool) {
        return bridgeData.transactionId != bytes32(0) && bytes(bridgeData.bridge).length > 0
            && bridgeData.receiver != address(0) && bridgeData.minAmount > 0 && bridgeData.destinationChainId != 0;
    }

    /**
     * @notice Validates a tuple of ILiFi.BridgeData and LibSwap.SwapData[],
     *         ensuring it represents valid and consistent swap-related data.
     * @dev Checks if the bridgeData itself is valid. Then, if bridgeData.hasSourceSwaps is true,
     *      it ensures swapDataArray is valid and non-empty. If bridgeData.hasSourceSwaps is false,
     *      it ensures swapDataArray is effectively empty (either 0-length or contains no non-empty swaps).
     * @param bridgeData The ILiFi.BridgeData struct.
     * @param swapDataArray The array of LibSwap.SwapData structs.
     * @return True if the tuple is valid and consistent swap data, false otherwise.
     */
    function isBridgeAndSwapDataTupleValid(ILiFi.BridgeData memory bridgeData, LibSwap.SwapData[] memory swapDataArray)
        internal
        pure
        returns (bool)
    {
        if (!isBridgeDataValid(bridgeData)) {
            return false;
        }

        if (bridgeData.hasSourceSwaps) {
            // If bridgeData indicates source swaps, the swapDataArray must be valid and contain actual swaps.
            return isSwapDataArrayValid(swapDataArray);
        } else {
            // If bridgeData indicates NO source swaps, then swapDataArray should be effectively empty
            // (i.e., not contain any "valid and non-empty" swaps).
            return !isSwapDataArrayValid(swapDataArray);
        }
    }

    /**
     * @notice Validates LiFi calldata by decoding it and checking the strategy.
     * @dev This function decodes the LiFi data and strategy from the input bytes,
     *      then uses TrailsLiFiFlagDecoder to validate it. It will revert if the data
     *      is invalid.
     * @param data The abi-encoded tuple of (TrailsDecodingStrategy, bytes).
     */
    function validate(bytes calldata data) internal pure {
        (TrailsDecodingStrategy strategy, bytes memory liFiData) = abi.decode(data, (TrailsDecodingStrategy, bytes));

        (ILiFi.BridgeData memory finalBridgeData, LibSwap.SwapData[] memory finalSwapDataArray) =
            TrailsLiFiFlagDecoder.decodeLiFiDataOrRevert(liFiData, strategy);

        if (strategy == TrailsDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE) {
            if (!isBridgeAndSwapDataTupleValid(finalBridgeData, finalSwapDataArray)) {
                revert InvalidLiFiData();
            }
        } else if (strategy == TrailsDecodingStrategy.SINGLE_BRIDGE_DATA) {
            if (!isBridgeDataValid(finalBridgeData)) {
                revert InvalidLiFiData();
            }
        } else if (strategy == TrailsDecodingStrategy.SWAP_DATA_ARRAY) {
            if (!isSwapDataArrayValid(finalSwapDataArray)) {
                revert InvalidLiFiData();
            }
        } else if (strategy == TrailsDecodingStrategy.SINGLE_SWAP_DATA) {
            if (finalSwapDataArray.length != 1 || !isSwapDataValid(finalSwapDataArray[0])) {
                revert InvalidLiFiData();
            }
        }
    }
}
