// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

// -------------------------------------------------------------------------
// Structs
// -------------------------------------------------------------------------

struct TrailsExecutionInfo {
    address originToken;
    uint256 amount;
    uint256 originChainId;
    uint256 destinationChainId;
}
