// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {ILiFi} from "lifi-contracts/interfaces/ILiFi.sol";
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
     *      The calling contract should use try/catch if it needs to handle such reverts.
     * @param data Full calldata including 4-byte function selector, passed as memory.
     * @return bridgeDataOut The decoded BridgeData struct, or a default one if data is too short.
     * @return swapDataOut The decoded SwapData array, or an empty one if not present or data is too short.
     */
    function tryDecodeBridgeAndSwapData(bytes memory data)
        external
        view
        returns (ILiFi.BridgeData memory bridgeDataOut, LibSwap.SwapData[] memory swapDataOut)
    {
        // bridgeDataOut is implicitly zero-initialized by Solidity.
        swapDataOut = new LibSwap.SwapData[](0); // Initialize to empty array.

        // Minimum length for selector (4) + two offsets (32 each) = 68 bytes for a tuple
        uint256 minLenForTupleOffsets = 4 + 32 + 32;
        // Minimum length for selector (4) + one offset (32) = 36 bytes for BridgeData only
        uint256 minLenForBridgeDataOffset = 4 + 32;

        if (data.length >= minLenForTupleOffsets) {
            // Data is long enough to potentially be a (BridgeData, SwapData[]) tuple.
            bytes memory tupleBytes = _getMemorySlice(data, 4); // Strip selector
            // This abi.decode will REVERT if tupleBytes is not a valid encoding for the tuple.
            (bridgeDataOut, swapDataOut) = abi.decode(tupleBytes, (ILiFi.BridgeData, LibSwap.SwapData[]));
            // If we reach here, decoding was successful.
        } else if (data.length >= minLenForBridgeDataOffset) {
            // Data is not long enough for a tuple, but might be for BridgeData alone.
            bytes memory bridgeDataOnlyBytes = _getMemorySlice(data, 4); // Strip selector
            // This abi.decode will REVERT if bridgeDataOnlyBytes is not a valid encoding for BridgeData.
            (bridgeDataOut) = abi.decode(bridgeDataOnlyBytes, (ILiFi.BridgeData));
            // If we reach here, decoding was successful; swapDataOut remains empty.
        }
        // If data.length < minLenForBridgeDataOffset, both bridgeDataOut (implicitly)
        // and swapDataOut (explicitly) will be their default/empty values.

        return (bridgeDataOut, swapDataOut);
    }
}
