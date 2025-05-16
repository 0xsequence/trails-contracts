// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";

/**
 * @title AnypayLiFiDecoder
 * @author Shun Kakinoki
 * @notice Library to decode ILiFi.BridgeData and LibSwap.SwapData[] from calldata.
 */
library AnypayLiFiDecoder {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error SliceOutOfBounds();
    error NoLiFiDataDecoded();
    error CalldataTooShortForPayload();

    // -------------------------------------------------------------------------
    // Internal Helper Functions
    // -------------------------------------------------------------------------
    /**
     * @dev Copies a slice of a bytes memory array to a new bytes memory array.
     * @param data The source bytes array.
     * @param start The starting index (0-based) of the slice in the source array.
     * @return A new bytes memory array containing the slice.
     */
    function _getMemorySlice(bytes memory data, uint256 start) internal pure returns (bytes memory) {
        if (start > data.length) {
            revert SliceOutOfBounds();
        }
        uint256 len = data.length - start;
        bytes memory slice = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            slice[i] = data[start + i];
        }
        return slice;
    }

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Attempts to decode (ILiFi.BridgeData, LibSwap.SwapData[]) or just ILiFi.BridgeData from calldata.
     * @dev Returns default/empty structs if calldata is too short for required offsets.
     *      If calldata is long enough for offsets but malformed for abi.decode, this function WILL REVERT.
     * @param data Full calldata including 4-byte function selector, passed as memory.
     * @return bridgeDataOut The decoded BridgeData struct, or a default one if data is too short.
     * @return swapDataOut The decoded SwapData array, or an empty one if not present or data is too short.
     */
    function tryDecodeBridgeAndSwapData(bytes memory data)
        public
        pure
        returns (ILiFi.BridgeData memory bridgeDataOut, LibSwap.SwapData[] memory swapDataOut)
    {
        swapDataOut = new LibSwap.SwapData[](0);

        uint256 minLenForTupleOffsets = 4 + 32 + 32;
        uint256 minLenForBridgeDataOffset = 4 + 32;

        if (data.length >= minLenForTupleOffsets) {
            bytes memory tupleBytes = _getMemorySlice(data, 4);
            (bridgeDataOut, swapDataOut) = abi.decode(tupleBytes, (ILiFi.BridgeData, LibSwap.SwapData[]));
        } else if (data.length >= minLenForBridgeDataOffset) {
            bytes memory bridgeDataOnlyBytes = _getMemorySlice(data, 4);
            (bridgeDataOut) = abi.decode(bridgeDataOnlyBytes, (ILiFi.BridgeData));
        }
        return (bridgeDataOut, swapDataOut);
    }
  
    /**
     * @notice Decodes the LiFi payload (6th argument onwards) as LibSwap.SwapData[].
     * @dev Assumes a standard prefix of (bytes32, string, string, address, uint256).
     *      Reverts if calldata is too short or if abi.decode fails for the specific structure.
     * @param data The complete calldata for the function call, including the 4-byte selector.
     * @return swapDataArrayOut The decoded LibSwap.SwapData array.
     */
    function decodeLifiSwapDataPayloadAsArray(bytes memory data)
        public
        pure
        returns (LibSwap.SwapData[] memory swapDataArrayOut)
    {
        uint256 minCalldataLenForPrefixAndOneOffset = 4 + (6 * 32);
        if (data.length < minCalldataLenForPrefixAndOneOffset) {
            revert CalldataTooShortForPayload();
        }
        bytes memory argsData = _getMemorySlice(data, 4);
        (, , , , , swapDataArrayOut) = abi.decode(argsData, (bytes32, string, string, address, uint256, LibSwap.SwapData[]));
        return swapDataArrayOut;
    }

    /**
     * @notice Decodes the LiFi payload (6th argument onwards) as a single LibSwap.SwapData struct.
     * @dev Assumes a standard prefix of (bytes32, string, string, address, uint256).
     *      Reverts if calldata is too short or if abi.decode fails for the specific structure.
     * @param data The complete calldata for the function call, including the 4-byte selector.
     * @return singleSwapDataOut The decoded LibSwap.SwapData struct.
     */
    function decodeLifiSwapDataPayloadAsSingle(bytes memory data)
        public
        pure
        returns (LibSwap.SwapData memory singleSwapDataOut)
    {
        uint256 minCalldataLenForPrefixAndOneOffset = 4 + (6 * 32);
        if (data.length < minCalldataLenForPrefixAndOneOffset) {
            revert CalldataTooShortForPayload();
        }
        bytes memory argsData = _getMemorySlice(data, 4);
        (, , , , , singleSwapDataOut) = abi.decode(argsData, (bytes32, string, string, address, uint256, LibSwap.SwapData));
        return singleSwapDataOut;
    }

    /**
     * @notice Decodes swap data from calldata using multiple strategies, reverting if no data is found OR if an intermediate decoding step fails.
     * @dev Sequentially attempts different decoding patterns:
     *      1. `tryDecodeBridgeAndSwapData`
     *      2. `decodeLifiSwapDataPayloadAsArray`
     *      3. `decodeLifiSwapDataPayloadAsSingle`
     *      If a step finds valid SwapData, it returns. If a step encounters an unrecoverable error (e.g., abi.decode failure),
     *      this function will revert at that point. If all steps complete without finding SwapData, it reverts with `NoSwapDataDecoded`.
     * @param data The complete calldata for the function call, including the 4-byte selector.
     * @return finalBridgeData The decoded ILiFi.BridgeData struct. Populated if the first decoding strategy is used and successful.
     * @return finalSwapDataArray The decoded LibSwap.SwapData array. Will not be empty if the function doesn't revert.
     */
    function decodeLiFiDataOrRevert(bytes memory data)
        external
        pure
        returns (ILiFi.BridgeData memory finalBridgeData, LibSwap.SwapData[] memory finalSwapDataArray)
    {
        // finalBridgeData is implicitly initialized to default.
        // It will be populated ONLY if tryDecodeBridgeAndSwapData succeeds without reverting.

        // Attempt 1: Using tryDecodeBridgeAndSwapData
        try tryDecodeBridgeAndSwapData(data) returns (ILiFi.BridgeData memory bd, LibSwap.SwapData[] memory sd) {
            finalBridgeData = bd; // Store bridge data if this attempt doesn't revert
            if (sd.length > 0) {
                finalSwapDataArray = sd;
                return (finalBridgeData, finalSwapDataArray);
            }
            // If no swaps found here, finalBridgeData is set, continue to other strategies for swaps.
        } catch {
            // tryDecodeBridgeAndSwapData reverted (e.g., ABI decode error).
            // finalBridgeData remains default. Proceed to other strategies for swaps.
        }

        // Attempt 2: Using decodeLifiSwapDataPayloadAsArray
        // This attempt will use the finalBridgeData (either populated from Attempt 1 or default).
        try decodeLifiSwapDataPayloadAsArray(data) returns (LibSwap.SwapData[] memory sDataArr) {
            if (sDataArr.length > 0) {
                finalSwapDataArray = sDataArr;
                return (finalBridgeData, finalSwapDataArray);
            }
        } catch {
            // decodeLifiSwapDataPayloadAsArray reverted. Proceed.
        }

        // Attempt 3: Using decodeLifiSwapDataPayloadAsSingle
        try decodeLifiSwapDataPayloadAsSingle(data) returns (LibSwap.SwapData memory sDataSingle) {
            if (sDataSingle.callTo != address(0)) { // Basic validity check for a populated struct
                finalSwapDataArray = new LibSwap.SwapData[](1);
                finalSwapDataArray[0] = sDataSingle;
                return (finalBridgeData, finalSwapDataArray);
            }
        } catch {
            // decodeLifiSwapDataPayloadAsSingle reverted.
        }

        // If no swap data was found and returned by any strategy.
        revert NoLiFiDataDecoded();
    }
}
