// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";

/**
 * @title AnypayLiFiDecodingLogic
 * @author Shun Kakinoki
 * @notice Library containing the core decoding logic for ILiFi.BridgeData and LibSwap.SwapData[].
 *         This library's functions are designed to be called externally, often within a try/catch block.
 */
library AnypayLiFiDecodingLogic {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------
    error SliceOutOfBounds();
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
    // Public Decoding Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Attempts to decode (ILiFi.BridgeData, LibSwap.SwapData[]) or just ILiFi.BridgeData from calldata.
     * @dev Returns default/empty structs if calldata is too short for required offsets.
     *      If calldata is long enough for offsets but malformed for abi.decode, this function WILL REVERT.
     * @param data Full calldata including 4-byte function selector, passed as memory.
     * @return bridgeDataOut The decoded BridgeData struct, or a default one if data is too short.
     * @return swapDataOut The decoded SwapData array, or an empty one if not present or data is too short.
     */
    function decodeBridgeAndSwapData(bytes memory data)
        public
        pure
        returns (ILiFi.BridgeData memory bridgeDataOut, LibSwap.SwapData[] memory swapDataOut)
    {
        swapDataOut = new LibSwap.SwapData[](0);

        uint256 minLenForTupleOffsets = 4 + 32 + 32; // selector + offset_bridgeData + offset_swapData
        uint256 minLenForBridgeDataOffset = 4 + 32; // selector + offset_bridgeData

        if (data.length >= minLenForTupleOffsets) {
            bytes memory tupleBytes = _getMemorySlice(data, 4); // Skip selector
            (bridgeDataOut, swapDataOut) = abi.decode(tupleBytes, (ILiFi.BridgeData, LibSwap.SwapData[]));
        } else if (data.length >= minLenForBridgeDataOffset) {
            bytes memory bridgeDataOnlyBytes = _getMemorySlice(data, 4); // Skip selector
            (bridgeDataOut) = abi.decode(bridgeDataOnlyBytes, (ILiFi.BridgeData));
        }
        // If neither condition met, bridgeDataOut remains default, swapDataOut is already empty.
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
        // 4 (selector) + 5 * 32 (prefix args) + 32 (offset to SwapData[])
        uint256 minCalldataLenForPrefixAndOneOffset = 4 + (6 * 32);
        if (data.length < minCalldataLenForPrefixAndOneOffset) {
            revert CalldataTooShortForPayload();
        }
        bytes memory argsData = _getMemorySlice(data, 4); // Skip selector
        (,,,,, swapDataArrayOut) = abi.decode(argsData, (bytes32, string, string, address, uint256, LibSwap.SwapData[]));
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
        // 4 (selector) + 5 * 32 (prefix args) + 32 (offset to SwapData)
        // (Though SwapData itself might be complex, the offset to it is one slot)
        uint256 minCalldataLenForPrefixAndOneOffset = 4 + (6 * 32);
        if (data.length < minCalldataLenForPrefixAndOneOffset) {
            revert CalldataTooShortForPayload();
        }
        bytes memory argsData = _getMemorySlice(data, 4); // Skip selector
        (,,,,, singleSwapDataOut) = abi.decode(argsData, (bytes32, string, string, address, uint256, LibSwap.SwapData));
        return singleSwapDataOut;
    }
}

/**
 * @title AnypayLiFiDecoder
 * @author Shun Kakinoki
 * @notice Library to decode ILiFi.BridgeData and LibSwap.SwapData[] from calldata,
 *         using a try/catch pattern for robustness with arbitrary calldata.
 */
library AnypayLiFiDecoder {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------
    error NoLiFiDataDecoded(); // Specific to this orchestrator's logic

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Attempts to decode (ILiFi.BridgeData, LibSwap.SwapData[]) or just ILiFi.BridgeData from calldata.
     * @dev Calls AnypayLiFiDecodingLogic.decodeBridgeAndSwapData within a try/catch block.
     * @param data Full calldata including 4-byte function selector, passed as memory.
     * @return success True if decoding was successful, false otherwise.
     * @return bridgeDataOut The decoded BridgeData struct, or a default one if decoding failed.
     * @return swapDataOut The decoded SwapData array, or an empty one if decoding failed or not present.
     */
    function tryDecodeBridgeAndSwapData(bytes memory data)
        public
        pure
        returns (bool success, ILiFi.BridgeData memory bridgeDataOut, LibSwap.SwapData[] memory swapDataOut)
    {
        try AnypayLiFiDecodingLogic.decodeBridgeAndSwapData(data) returns (
            ILiFi.BridgeData memory bd, LibSwap.SwapData[] memory sd
        ) {
            return (true, bd, sd);
        } catch {
            return (false, bridgeDataOut, swapDataOut);
        }
    }

    /**
     * @notice Attempts to decode the LiFi payload (6th argument onwards) as LibSwap.SwapData[].
     * @dev Calls AnypayLiFiDecodingLogic.decodeLifiSwapDataPayloadAsArray within a try/catch block.
     * @param data The complete calldata for the function call, including the 4-byte selector.
     * @return success True if decoding was successful, false otherwise.
     * @return swapDataArrayOut The decoded LibSwap.SwapData array, or an empty one if decoding failed.
     */
    function tryDecodeLifiSwapDataPayloadAsArray(bytes memory data)
        public
        pure
        returns (bool success, LibSwap.SwapData[] memory swapDataArrayOut)
    {
        try AnypayLiFiDecodingLogic.decodeLifiSwapDataPayloadAsArray(data) returns (LibSwap.SwapData[] memory sDataArr)
        {
            return (true, sDataArr);
        } catch {
            return (false, swapDataArrayOut);
        }
    }

    /**
     * @notice Attempts to decode the LiFi payload (6th argument onwards) as a single LibSwap.SwapData struct.
     * @dev Calls AnypayLiFiDecodingLogic.decodeLifiSwapDataPayloadAsSingle within a try/catch block.
     * @param data The complete calldata for the function call, including the 4-byte selector.
     * @return success True if decoding was successful, false otherwise.
     * @return singleSwapDataOut The decoded LibSwap.SwapData struct, or a default one if decoding failed.
     */
    function tryDecodeLifiSwapDataPayloadAsSingle(bytes memory data)
        public
        pure
        returns (bool success, LibSwap.SwapData memory singleSwapDataOut)
    {
        try AnypayLiFiDecodingLogic.decodeLifiSwapDataPayloadAsSingle(data) returns (
            LibSwap.SwapData memory sDataSingle
        ) {
            return (true, sDataSingle);
        } catch {
            return (false, singleSwapDataOut);
        }
    }

    /**
     * @notice Decodes swap data from calldata using multiple strategies, reverting if no data is found OR if an intermediate decoding step fails.
     * @dev Sequentially attempts different decoding patterns by calling functions from AnypayLiFiDecodingLogic:
     *      1. `AnypayLiFiDecodingLogic.tryDecodeBridgeAndSwapData`
     *      2. `AnypayLiFiDecodingLogic.tryDecodeLifiSwapDataPayloadAsArray`
     *      3. `AnypayLiFiDecodingLogic.tryDecodeLifiSwapDataPayloadAsSingle`
     *      If a step finds valid SwapData, it returns. If a step encounters an unrecoverable error (e.g., abi.decode failure),
     *      this function will revert at that point (due to the external call reverting).
     *      If all strategies complete without finding SwapData suitable for return, it reverts with `NoLiFiDataDecoded`.
     * @param data The complete calldata for the function call, including the 4-byte selector.
     * @return finalBridgeData The decoded ILiFi.BridgeData struct. Populated if the first decoding strategy is used and successful.
     * @return finalSwapDataArray The decoded LibSwap.SwapData array. Will not be empty if the function doesn't revert with NoLiFiDataDecoded.
     */
    function decodeLiFiDataOrRevert(bytes memory data)
        external
        pure
        returns (ILiFi.BridgeData memory finalBridgeData, LibSwap.SwapData[] memory finalSwapDataArray)
    {
        // finalBridgeData is implicitly initialized to default.
        // It will be populated ONLY if AnypayLiFiDecodingLogic.decodeBridgeAndSwapData succeeds.

        // Attempt 1: Using AnypayLiFiDecodingLogic.decodeBridgeAndSwapData
        try AnypayLiFiDecodingLogic.decodeBridgeAndSwapData(data) returns (
            ILiFi.BridgeData memory bd, LibSwap.SwapData[] memory sd
        ) {
            finalBridgeData = bd; // Store bridge data if this attempt doesn't revert
            if (sd.length > 0) {
                finalSwapDataArray = sd;
                return (finalBridgeData, finalSwapDataArray);
            }
            // If no swaps found here, finalBridgeData is set (if bd was populated). Continue to other strategies for swaps.
        } catch {
            // AnypayLiFiDecodingLogic.decodeBridgeAndSwapData reverted (e.g., ABI decode error or SliceOutOfBounds).
            // finalBridgeData remains default (or as it was if this catch is for a later attempt, though here it's the first).
            // Proceed to other strategies for swaps.
        }

        // Attempt 2: Using AnypayLiFiDecodingLogic.decodeLifiSwapDataPayloadAsArray
        // This attempt will use the finalBridgeData (either populated from Attempt 1 or default).
        try AnypayLiFiDecodingLogic.decodeLifiSwapDataPayloadAsArray(data) returns (LibSwap.SwapData[] memory sDataArr)
        {
            if (sDataArr.length > 0) {
                finalSwapDataArray = sDataArr;
                return (finalBridgeData, finalSwapDataArray);
            }
        } catch {
            // AnypayLiFiDecodingLogic.decodeLifiSwapDataPayloadAsArray reverted. Proceed.
        }

        // Attempt 3: Using AnypayLiFiDecodingLogic.decodeLifiSwapDataPayloadAsSingle
        try AnypayLiFiDecodingLogic.decodeLifiSwapDataPayloadAsSingle(data) returns (
            LibSwap.SwapData memory sDataSingle
        ) {
            // Basic validity check: ensure some data was decoded into the struct
            if (sDataSingle.callTo != address(0)) {
                finalSwapDataArray = new LibSwap.SwapData[](1);
                finalSwapDataArray[0] = sDataSingle;
                return (finalBridgeData, finalSwapDataArray);
            }
        } catch {
            // AnypayLiFiDecodingLogic.decodeLifiSwapDataPayloadAsSingle reverted.
        }

        // If no swap data was found and returned by any strategy.
        revert NoLiFiDataDecoded();
    }
}
