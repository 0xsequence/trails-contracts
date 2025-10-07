// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

// -------------------------------------------------------------------------
// Library
// -------------------------------------------------------------------------
library TrailsSentinelLib {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------
    bytes32 public constant SENTINEL_NAMESPACE = keccak256("org.sequence.trails.router.sentinel");
    bytes32 public constant SUCCESS_VALUE = bytes32(uint256(1));

    // -------------------------------------------------------------------------
    // Storage Slot Helpers
    // -------------------------------------------------------------------------
    function successSlot(bytes32 opHash) internal pure returns (bytes32) {
        return keccak256(abi.encode(SENTINEL_NAMESPACE, opHash));
    }
}
