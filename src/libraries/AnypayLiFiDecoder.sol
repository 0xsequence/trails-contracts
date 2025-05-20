// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {AnypayLiFiValidator} from "./AnypayLiFiValidator.sol";
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
    // Internal Decoding Functions (New Structure)
    // -------------------------------------------------------------------------

    /**
     * @notice Attempts to decode (ILiFi.BridgeData, LibSwap.SwapData[]) from calldata (selector skipped).
     * @dev This function will revert if abi.decode fails (e.g., calldata too short or malformed for the tuple).
     * @param data Calldata AFTER the 4-byte function selector.
     * @return bridgeDataOut The decoded BridgeData struct.
     * @return swapDataOut The decoded SwapData array.
     */
    function decodeAsBridgeDataAndSwapDataTuple(bytes memory data)
        external
        pure
        returns (ILiFi.BridgeData memory bridgeDataOut, LibSwap.SwapData[] memory swapDataOut)
    {
        (bridgeDataOut, swapDataOut) = abi.decode(data, (ILiFi.BridgeData, LibSwap.SwapData[]));
        return (bridgeDataOut, swapDataOut);
    }

    /**
     * @notice Attempts to decode a single ILiFi.BridgeData from calldata (selector skipped).
     * @dev This function will revert if abi.decode fails (e.g., calldata too short or malformed for the struct).
     * @param data Calldata AFTER the 4-byte function selector.
     * @return bridgeDataOut The decoded BridgeData struct.
     */
    function decodeAsSingleBridgeData(bytes memory data)
        external
        pure
        returns (ILiFi.BridgeData memory bridgeDataOut)
    {
        (bridgeDataOut) = abi.decode(data, (ILiFi.BridgeData));
        return bridgeDataOut;
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
        if (data.length < 4) {
            revert CalldataTooShortForPayload();
        }
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
        uint256 minCalldataLenForPrefixAndOneOffset = 4 + (6 * 32);
        if (data.length < 4) {
            revert CalldataTooShortForPayload();
        }
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
    // Private Helper Functions (for AnypayLiFiDecoder)
    // -------------------------------------------------------------------------
    /**
     * @dev Internal helper to get calldata slice after the selector.
     *      Returns empty bytes if data is too short for even a selector.
     */
    function _getCalldataAfterSelector(bytes memory data) private pure returns (bytes memory) {
        if (data.length < 4) {
            return bytes(""); // Return empty bytes, subsequent decodes will fail as expected
        }
        return AnypayLiFiDecodingLogic._getMemorySlice(data, 4);
    }

    // -------------------------------------------------------------------------
    // Public Try-Decode Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Attempts to decode (ILiFi.BridgeData, LibSwap.SwapData[]) from calldata.
     * @dev Calls AnypayLiFiDecodingLogic.decodeAsBridgeDataAndSwapDataTuple within a try/catch block.
     * @param data Full calldata including 4-byte function selector, passed as memory.
     * @return success True if decoding was successful, false otherwise.
     * @return bridgeDataOut The decoded BridgeData struct.
     * @return swapDataOut The decoded SwapData array.
     */
    function tryDecodeBridgeDataAndSwapDataTuple(bytes memory data)
        public
        pure
        returns (bool success, ILiFi.BridgeData memory bridgeDataOut, LibSwap.SwapData[] memory swapDataOut)
    {
        bytes memory calldataForDecode = _getCalldataAfterSelector(data);
        if (calldataForDecode.length == 0 && data.length > 0) {
            return (false, bridgeDataOut, swapDataOut);
        }

        try AnypayLiFiDecodingLogic.decodeAsBridgeDataAndSwapDataTuple(calldataForDecode) returns (
            ILiFi.BridgeData memory bd, LibSwap.SwapData[] memory sd
        ) {
            return (true, bd, sd);
        } catch {
            return (false, bridgeDataOut, swapDataOut);
        }
    }

    /**
     * @notice Attempts to decode a single ILiFi.BridgeData from calldata.
     * @dev Calls AnypayLiFiDecodingLogic.decodeAsSingleBridgeData within a try/catch block.
     * @param data Full calldata including 4-byte function selector, passed as memory.
     * @return success True if decoding was successful, false otherwise.
     * @return bridgeDataOut The decoded BridgeData struct.
     */
    function tryDecodeSingleBridgeData(bytes memory data)
        public
        pure
        returns (bool success, ILiFi.BridgeData memory bridgeDataOut)
    {
        bytes memory calldataForDecode = _getCalldataAfterSelector(data);
        if (calldataForDecode.length == 0 && data.length > 0) {
            // This case implies data had content but was too short for _getCalldataAfterSelector,
            // meaning it was shorter than 4 bytes. A direct decode attempt would fail.
            return (false, bridgeDataOut);
        }
        if (calldataForDecode.length == 0 && data.length == 0) {
            // If original data is also empty, it's a clear case for decode failure.
            return (false, bridgeDataOut);
        }


        try AnypayLiFiDecodingLogic.decodeAsSingleBridgeData(calldataForDecode) returns (ILiFi.BridgeData memory bd) {
            return (true, bd);
        } catch {
            return (false, bridgeDataOut);
        }
    }

    /**
     * @notice Attempts to decode the LiFi payload (6th argument onwards) as LibSwap.SwapData[] or a single LibSwap.SwapData.
     * @dev First tries to decode as LibSwap.SwapData[]. If that fails, tries LibSwap.SwapData.
     * @param data The complete calldata for the function call, including the 4-byte selector.
     * @return success True if any decoding was successful, false otherwise.
     * @return swapDataArrayOut The decoded LibSwap.SwapData array. If single struct is decoded, it's returned as a single-element array.
     */
    function tryDecodeLifiSwapDataPayload(bytes memory data)
        public
        pure
        returns (bool success, LibSwap.SwapData[] memory swapDataArrayOut)
    {
        // Attempt 1: Decode as LibSwap.SwapData[]
        try AnypayLiFiDecodingLogic.decodeLifiSwapDataPayloadAsArray(data) returns (LibSwap.SwapData[] memory sDataArr)
        {
            return (true, sDataArr);
        } catch {
            // First attempt failed, proceed to second.
        }

        // Attempt 2: Decode as single LibSwap.SwapData
        try AnypayLiFiDecodingLogic.decodeLifiSwapDataPayloadAsSingle(data) returns (
            LibSwap.SwapData memory sDataSingle
        ) {
            // If successful, wrap the single struct in an array
            swapDataArrayOut = new LibSwap.SwapData[](1);
            swapDataArrayOut[0] = sDataSingle;
            return (true, swapDataArrayOut);
        } catch {
            // Both attempts failed.
            return (false, swapDataArrayOut);
        }
    }

    /**
     * @notice Decodes swap data from calldata using multiple strategies, reverting if no data is found OR if an intermediate decoding step fails.
     * @dev Sequentially attempts different decoding patterns:
     *      1. `tryDecodeBridgeDataAndSwapDataTuple`
     *      2. `tryDecodeSingleBridgeData` (if first fails to get BridgeData or if SwapData is empty)
     *      3. `tryDecodeLifiSwapDataPayload`
     *      If a step successfully decodes SwapData, it returns.
     *      If all strategies complete without finding SwapData suitable for return, it reverts with `NoLiFiDataDecoded`.
     *      BridgeData is populated if the first or second strategy finds it.
     * @param data The complete calldata for the function call, including the 4-byte selector.
     * @return finalBridgeData The decoded ILiFi.BridgeData struct. Populated if the first or second decoding strategy is used and successful.
     * @return finalSwapDataArray The decoded LibSwap.SwapData array. Will not be empty if the function doesn't revert with NoLiFiDataDecoded.
     */
    function decodeLiFiDataOrRevert(bytes memory data)
        external
        pure
        returns (ILiFi.BridgeData memory finalBridgeData, LibSwap.SwapData[] memory finalSwapDataArray)
    {
        bool success;
        ILiFi.BridgeData memory decodedBridgeData;
        LibSwap.SwapData[] memory decodedSwapData;

        // Attempt 1: Try decoding as (BridgeData, SwapData[])
        (success, decodedBridgeData, decodedSwapData) = tryDecodeBridgeDataAndSwapDataTuple(data);
        if (success) {
            finalBridgeData = decodedBridgeData;
            // Check if the decoded bridge and swap data tuple is valid
            if (AnypayLiFiValidator.isBridgeAndSwapDataTupleValid(finalBridgeData, decodedSwapData)) {
                finalSwapDataArray = decodedSwapData;
                return (finalBridgeData, finalSwapDataArray);
            }
        }

        // Attempt 2: Try decoding as single (BridgeData)
        if (finalBridgeData.transactionId == bytes32(0)) {
            bool singleBdSuccess;
            ILiFi.BridgeData memory singleBd;
            (singleBdSuccess, singleBd) = tryDecodeSingleBridgeData(data);
            if (singleBdSuccess) {
                finalBridgeData = singleBd;
                // Check if the decoded bridge data is valid, return empty swap data
                if (AnypayLiFiValidator.isBridgeDataValid(finalBridgeData)) {
                    return (finalBridgeData, decodedSwapData);
                }
            }
        }

        // Attempt 3: Try decoding payload as (SwapData[]) or single (SwapData)
        (success, decodedSwapData) = tryDecodeLifiSwapDataPayload(data);
        if (success && decodedSwapData.length > 0) {
            // Check if the decoded swap data is non-empty (for single struct case)
            if (decodedSwapData.length == 1) {
                LibSwap.SwapData memory singleSwap = decodedSwapData[0];
                // Check if the decoded swap data is valid, return empty bridge data
                if (
                    AnypayLiFiValidator.isSwapDataValid(singleSwap)
                ) {
                    finalSwapDataArray = decodedSwapData;
                    return (finalBridgeData, finalSwapDataArray);
                }
            } else if (decodedSwapData.length > 1) { 
                // Check if the decoded swap data is valid, return empty bridge data
                if (AnypayLiFiValidator.isSwapDataArrayValid(decodedSwapData)) {
                    finalSwapDataArray = decodedSwapData;
                    return (finalBridgeData, finalSwapDataArray);
                }
            }
        }

        // If no swap data was found and returned by any strategy.
        revert NoLiFiDataDecoded();
    }
}
