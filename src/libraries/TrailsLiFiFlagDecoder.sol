// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {TrailsLiFiValidator} from "@/libraries/TrailsLiFiValidator.sol";
import {TrailsDecodingStrategy} from "@/interfaces/TrailsLiFi.sol";

/**
 * @title TrailsLiFiFlagDecoder
 * @author Shun Kakinoki
 * @notice Library to decode ILiFi.BridgeData and LibSwap.SwapData[] from calldata with efficient flag-based decoding.
 */
library TrailsLiFiFlagDecoder {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error SliceOutOfBounds();
    error CalldataTooShortForPayload();
    error InvalidDecodingStrategy();
    error InvalidLiFiData();

    // -------------------------------------------------------------------------
    // Internal Helper Functions
    // -------------------------------------------------------------------------
    /**
     * @dev Copies a slice of a bytes memory array to a new bytes memory array.
     * @param data The source bytes array.
     * @param start The starting index (0-based) of the slice in the source array.
     * @return copy A new bytes memory array containing the slice.
     */
    function getMemorySlice(bytes memory data, uint256 start) internal pure returns (bytes memory copy) {
        if (start > data.length) {
            revert SliceOutOfBounds();
        }

        assembly ("memory-safe") {
            let fmp := mload(0x40)
            copy := fmp

            let slice_len := sub(mload(data), start)

            mstore(fmp, slice_len)
            mcopy(add(fmp, 0x20), add(add(data, 0x20), start), slice_len)

            let padded_len := mul(div(add(slice_len, 31), 32), 32)
            let new_fmp := add(add(fmp, padded_len), 0x20)
            mstore(0x40, new_fmp)
        }
    }

    // -------------------------------------------------------------------------
    // Internal Decoding Functions
    // -------------------------------------------------------------------------

    /**
     * @dev Decodes (ILiFi.BridgeData, LibSwap.SwapData[]) from calldata (selector skipped).
     * @param data Calldata AFTER the 4-byte function selector.
     * @return bridgeDataOut The decoded BridgeData struct.
     * @return swapDataOut The decoded SwapData array.
     */
    function decodeAsBridgeDataAndSwapDataTuple(bytes calldata data)
        internal
        pure
        returns (ILiFi.BridgeData memory bridgeDataOut, LibSwap.SwapData[] memory swapDataOut)
    {
        (bridgeDataOut, swapDataOut) = abi.decode(data, (ILiFi.BridgeData, LibSwap.SwapData[]));
    }

    /**
     * @dev Decodes a single ILiFi.BridgeData from calldata (selector skipped).
     * @param data Calldata AFTER the 4-byte function selector.
     * @return bridgeDataOut The decoded BridgeData struct.
     */
    function decodeAsSingleBridgeData(bytes calldata data)
        internal
        pure
        returns (ILiFi.BridgeData memory bridgeDataOut)
    {
        bridgeDataOut = abi.decode(data, (ILiFi.BridgeData));
    }

    /**
     * @dev Decodes the LiFi payload (6th argument onwards) as LibSwap.SwapData[].
     * @param data The complete calldata for the function call, AFTER the 4-byte selector.
     * @return swapDataArrayOut The decoded LibSwap.SwapData array.
     */
    function decodeLifiSwapDataPayloadAsArray(bytes calldata data)
        internal
        pure
        returns (LibSwap.SwapData[] memory swapDataArrayOut)
    {
        // Minimum length for the prefix (5 args * 32 bytes) and one offset for the SwapData[] array itself.
        uint256 minCalldataLenForPrefixAndOneOffset = (5 * 32) + 32;
        if (data.length < minCalldataLenForPrefixAndOneOffset) {
            revert CalldataTooShortForPayload();
        }
        (,,,,, swapDataArrayOut) = abi.decode(data, (bytes32, string, string, address, uint256, LibSwap.SwapData[]));
    }

    /**
     * @dev Decodes the LiFi payload (6th argument onwards) as a single LibSwap.SwapData struct.
     * @param data The complete calldata for the function call, AFTER the 4-byte selector.
     * @return singleSwapDataOut The decoded LibSwap.SwapData struct.
     */
    function decodeLifiSwapDataPayloadAsSingle(bytes calldata data)
        internal
        pure
        returns (LibSwap.SwapData memory singleSwapDataOut)
    {
        uint256 minCalldataLenForPrefixAndOneOffset = 4 + (6 * 32);
        if (data.length < 4) {
            revert CalldataTooShortForPayload();
        }
        if (data.length < minCalldataLenForPrefixAndOneOffset) {
            revert CalldataTooShortForPayload();
        }
        (,,,,, singleSwapDataOut) = abi.decode(data, (bytes32, string, string, address, uint256, LibSwap.SwapData));
    }

    // -------------------------------------------------------------------------
    // Private Helper Functions
    // -------------------------------------------------------------------------
    /**
     * @dev Internal helper to get calldata slice after the selector.
     *      Returns empty bytes if data is too short for even a selector.
     */
    function getCalldataAfterSelector(bytes memory data) private pure returns (bytes memory) {
        if (data.length < 4) {
            return bytes("");
        }
        return getMemorySlice(data, 4);
    }

    // -------------------------------------------------------------------------
    // Main Decoding Function
    // -------------------------------------------------------------------------

    /**
     * @notice Decodes LiFi data from calldata using a specific strategy, reverting if decoding fails.
     * @dev Uses the specified decoding strategy to decode the data. Only one strategy is attempted based on the flag.
     * @param data The complete calldata for the function call, including the 4-byte selector.
     * @param strategy The decoding strategy to use.
     * @return finalBridgeData The decoded ILiFi.BridgeData struct. Will be empty for swap data strategies.
     * @return finalSwapDataArray The decoded LibSwap.SwapData array. Will be empty for SINGLE_BRIDGE_DATA strategy.
     */
    function decodeLiFiDataOrRevert(bytes calldata data, TrailsDecodingStrategy strategy)
        external
        pure
        returns (ILiFi.BridgeData memory finalBridgeData, LibSwap.SwapData[] memory finalSwapDataArray)
    {
        if (data.length < 4) {
            revert CalldataTooShortForPayload();
        }
        bytes calldata calldataAfterSelector = data[4:];

        if (strategy == TrailsDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE) {
            // Decode as (BridgeData, SwapData[])
            (finalBridgeData, finalSwapDataArray) = decodeAsBridgeDataAndSwapDataTuple(calldataAfterSelector);

            // Validate the decoded data
            if (!TrailsLiFiValidator.isBridgeAndSwapDataTupleValid(finalBridgeData, finalSwapDataArray)) {
                revert InvalidLiFiData();
            }
        } else if (strategy == TrailsDecodingStrategy.SINGLE_BRIDGE_DATA) {
            // Decode as single BridgeData
            finalBridgeData = decodeAsSingleBridgeData(calldataAfterSelector);

            // Validate the decoded data
            if (!TrailsLiFiValidator.isBridgeDataValid(finalBridgeData)) {
                revert InvalidLiFiData();
            }
        } else if (strategy == TrailsDecodingStrategy.SWAP_DATA_ARRAY) {
            // Decode payload as SwapData[]
            // For SWAP_DATA_ARRAY and SINGLE_SWAP_DATA, the abi.decode expects the *arguments* part of calldata.
            // The original calldata 'data' includes the selector. The slice 'calldataAfterSelector' is what we need.
            finalSwapDataArray = decodeLifiSwapDataPayloadAsArray(calldataAfterSelector);

            // Validate the decoded data
            if (!TrailsLiFiValidator.isSwapDataArrayValid(finalSwapDataArray)) {
                revert InvalidLiFiData();
            }
        } else if (strategy == TrailsDecodingStrategy.SINGLE_SWAP_DATA) {
            // Decode payload as single SwapData
            LibSwap.SwapData memory singleSwapData = decodeLifiSwapDataPayloadAsSingle(calldataAfterSelector);

            // Validate the decoded data
            if (!TrailsLiFiValidator.isSwapDataValid(singleSwapData)) {
                revert InvalidLiFiData();
            }

            // Convert single SwapData to array
            finalSwapDataArray = new LibSwap.SwapData[](1);
            finalSwapDataArray[0] = singleSwapData;
        } else {
            revert InvalidDecodingStrategy();
        }
    }
}
