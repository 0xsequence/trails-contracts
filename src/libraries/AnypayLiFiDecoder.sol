// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ILiFi} from "lifi-contracts/interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";

/**
 * @title AnypayLiFiDecoder
 * @notice Library to decode ILiFi.BridgeData and LibSwap.SwapData[] from calldata.
 */
library AnypayLiFiDecoder {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------
    error InvalidCalldataLengthForBridgeData();
    error SliceOutOfBounds();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------
    event DecodedBridgeData(bytes32 transactionId, address receiver, uint256 destinationChainId);
    event DecodedSwapData(address callTo, address sendingAssetId, address receivingAssetId, uint256 fromAmount, uint256 numSwaps);

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
     * @notice Decode only the first argument (ILiFi.BridgeData) from arbitrary calldata
     * @param data Full calldata including 4-byte function selector, passed as memory
     */
    function decodeOnlyBridgeData(bytes memory data) internal pure returns (ILiFi.BridgeData memory bd) {
        // Check if calldata is long enough for selector + one 32-byte offset
        if (data.length < 4 + 32) revert InvalidCalldataLengthForBridgeData();
        
        bytes memory bridgeDataBytes = _getMemorySlice(data, 4);
        (bd) = abi.decode(bridgeDataBytes, (ILiFi.BridgeData));
    }

    /**
     * @notice Emits decoded fields from BridgeData
     * @param data Calldata passed to LiFi-style function (e.g. bridge(BridgeData, X, Y)), passed as memory
     */
    function emitDecodedBridgeData(bytes memory data) internal {
        ILiFi.BridgeData memory bd = decodeOnlyBridgeData(data);
        emit DecodedBridgeData(bd.transactionId, bd.receiver, bd.destinationChainId);
    }

    /**
     * @notice Attempts to decode (ILiFi.BridgeData, LibSwap.SwapData[]) from calldata.
     * @dev This function can revert if calldata doesn't conform to the expected tuple structure (e.g. abi.decode panic).
     * @param data Full calldata including 4-byte function selector, passed as memory.
     * @return swapDataOut The decoded SwapData array if successful.
     */
    function decodeSwapDataTuple(bytes memory data)
        internal
        view
        returns (LibSwap.SwapData[] memory swapDataOut)
    {
        // Basic check: selector (4) + offset_bd (32) + offset_sd (32) = 68 bytes.
        // If calldata is shorter, it cannot hold offsets for two dynamic parameters.
        if (data.length < 4 + (2 * 32)) {
            return new LibSwap.SwapData[](0);
        }

        bytes memory tupleBytes = _getMemorySlice(data, 4);
        // This abi.decode attempts to parse tupleBytes as (ILiFi.BridgeData, LibSwap.SwapData[]).
        // It will revert (e.g., with panic 0x41) if the calldata is not structured accordingly.
        (, LibSwap.SwapData[] memory _decodedSwapData) = abi.decode(tupleBytes, (ILiFi.BridgeData, LibSwap.SwapData[]));
        return _decodedSwapData;
    }
} 