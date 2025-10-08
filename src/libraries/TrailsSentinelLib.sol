// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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
    function successSlot(bytes32 opHash) internal pure returns (bytes32 result) {
        // return keccak256(abi.encode(SENTINEL_NAMESPACE, opHash));
        bytes32 namespace = SENTINEL_NAMESPACE;
        assembly {
            mstore(0x00, namespace)
            mstore(0x20, opHash)
            result := keccak256(0x00, 0x40)
        }
    }
}
