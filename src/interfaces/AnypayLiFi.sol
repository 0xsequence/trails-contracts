// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

// -------------------------------------------------------------------------
// Structs
// -------------------------------------------------------------------------

struct AnypayLiFiInfo {
    address originToken;
    uint256 amount;
    uint256 originChainId;
    uint256 destinationChainId;
}

// -------------------------------------------------------------------------
// Enums
// -------------------------------------------------------------------------

/**
 * @notice Enum to specify the decoding strategy for LiFi data
 * @param BRIDGE_DATA_AND_SWAP_DATA_TUPLE Decode as (BridgeData, SwapData[])
 * @param SINGLE_BRIDGE_DATA Decode as single BridgeData
 * @param SWAP_DATA_ARRAY Decode payload as SwapData[]
 * @param SINGLE_SWAP_DATA Decode payload as single SwapData
 */
enum AnypayDecodingStrategy {
    BRIDGE_DATA_AND_SWAP_DATA_TUPLE,
    SINGLE_BRIDGE_DATA,
    SWAP_DATA_ARRAY,
    SINGLE_SWAP_DATA
}
