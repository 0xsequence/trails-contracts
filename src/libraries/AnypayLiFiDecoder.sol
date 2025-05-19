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
     * @notice Attempts to decode ILiFi.BridgeData and optionally LibSwap.SwapData[] from calldata.
     * @dev Tries to decode as (ILiFi.BridgeData, LibSwap.SwapData[]) first.
     *      If that fails, tries to decode as a single ILiFi.BridgeData.
     * @param data Full calldata including 4-byte function selector, passed as memory.
     * @return success True if any decoding was successful, false otherwise.
     * @return bridgeDataOut The decoded BridgeData struct, or a default one if decoding failed.
     * @return swapDataOut The decoded SwapData array, or an empty one if decoding failed or not present.
     */
    function tryDecodeBridgeAndSwapData(bytes memory data)
        public
        pure
        returns (bool success, ILiFi.BridgeData memory bridgeDataOut, LibSwap.SwapData[] memory swapDataOut)
    {
        bytes memory calldataForDecode = _getCalldataAfterSelector(data);
        if (calldataForDecode.length == 0 && data.length > 0) {
            return (false, bridgeDataOut, swapDataOut);
        }

        // Attempt 1: Decode as (BridgeData, SwapData[]) (with swap data)
        try AnypayLiFiDecodingLogic.decodeAsBridgeDataAndSwapDataTuple(calldataForDecode) returns (
            ILiFi.BridgeData memory bd, LibSwap.SwapData[] memory sd
        ) {
            return (true, bd, sd);
        } catch {
            // First attempt failed, proceed to second.
        }

        // Attempt 2: Decode as single BridgeData (no swap data)
        try AnypayLiFiDecodingLogic.decodeAsSingleBridgeData(calldataForDecode) returns (ILiFi.BridgeData memory bd) {
            // Success, but no swap data from this specific decode.
            // swapDataOut is already initialized to an empty array.
            return (true, bd, swapDataOut);
        } catch {
            // Both attempts failed.
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
     * @dev Sequentially attempts different decoding patterns:
     *      1. `tryDecodeBridgeAndSwapData` (which internally tries tuple then single BridgeData)
     *      2. `tryDecodeLifiSwapDataPayloadAsArray`
     *      3. `tryDecodeLifiSwapDataPayloadAsSingle`
     *      If a step successfully decodes SwapData, it returns.
     *      If all strategies complete without finding SwapData suitable for return, it reverts with `NoLiFiDataDecoded`.
     *      BridgeData is populated if the first strategy (tryDecodeBridgeAndSwapData) finds it.
     * @param data The complete calldata for the function call, including the 4-byte selector.
     * @return finalBridgeData The decoded ILiFi.BridgeData struct. Populated if the first decoding strategy is used and successful.
     * @return finalSwapDataArray The decoded LibSwap.SwapData array. Will not be empty if the function doesn't revert with NoLiFiDataDecoded.
     */
    function decodeLiFiDataOrRevert(bytes memory data)
        external
        pure
        returns (ILiFi.BridgeData memory finalBridgeData, LibSwap.SwapData[] memory finalSwapDataArray)
    {
        // Attempt 1: Using the refactored tryDecodeBridgeAndSwapData
        bool firstAttemptSuccess;
        ILiFi.BridgeData memory bridgeDataFromFirstAttempt;
        LibSwap.SwapData[] memory swapDataFromFirstAttempt;

        (firstAttemptSuccess, bridgeDataFromFirstAttempt, swapDataFromFirstAttempt) = tryDecodeBridgeAndSwapData(data);

        if (firstAttemptSuccess) {
            finalBridgeData = bridgeDataFromFirstAttempt;
            if (swapDataFromFirstAttempt.length > 0) {
                finalSwapDataArray = swapDataFromFirstAttempt;
                return (finalBridgeData, finalSwapDataArray);
            }
        }

        // Attempt 2: Using tryDecodeLifiSwapDataPayloadAsArray
        bool secondAttemptSuccess;
        LibSwap.SwapData[] memory swapDataFromSecondAttempt;
        (secondAttemptSuccess, swapDataFromSecondAttempt) = tryDecodeLifiSwapDataPayloadAsArray(data);

        if (secondAttemptSuccess && swapDataFromSecondAttempt.length > 0) {
            finalSwapDataArray = swapDataFromSecondAttempt;
            return (finalBridgeData, finalSwapDataArray);
        }

        // Attempt 3: Using tryDecodeLifiSwapDataPayloadAsSingle
        bool thirdAttemptSuccess;
        LibSwap.SwapData memory swapDataFromThirdAttempt;
        (thirdAttemptSuccess, swapDataFromThirdAttempt) = tryDecodeLifiSwapDataPayloadAsSingle(data);

        if (thirdAttemptSuccess) {
            // If any swap data was decoded, return it.
            if (
                swapDataFromThirdAttempt.callTo != address(0) || swapDataFromThirdAttempt.approveTo != address(0)
                    || swapDataFromThirdAttempt.fromAmount > 0
            ) {
                finalSwapDataArray = new LibSwap.SwapData[](1);
                finalSwapDataArray[0] = swapDataFromThirdAttempt;
                return (finalBridgeData, finalSwapDataArray);
            }
        }

        // If no swap data was found and returned by any strategy.
        revert NoLiFiDataDecoded();
    }
}
