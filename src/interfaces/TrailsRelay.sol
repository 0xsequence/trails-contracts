// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

struct TrailsRelayInfo {
    // From RelayData
    bytes32 requestId;
    bytes signature;
    bytes32 nonEVMReceiver;
    bytes32 receivingAssetId;
    // From BridgeData
    address sendingAssetId;
    address receiver;
    uint256 destinationChainId;
    uint256 minAmount;
    address target;
}
