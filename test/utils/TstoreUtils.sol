// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Vm} from "forge-std/Vm.sol";

// ----------------------------------------------------------------------------
// Cheatcode handle (usable from non-Test contexts in test scope)
// ----------------------------------------------------------------------------

address constant HEVM_ADDRESS = address(uint160(uint256(keccak256("hevm cheat code"))));
Vm constant HEVM = Vm(HEVM_ADDRESS);

// ----------------------------------------------------------------------------
// Transient Storage Helpers
// ----------------------------------------------------------------------------

/// @notice Helper to write transient storage at a given slot
contract TstoreSetter {
    function set(bytes32 slot, bytes32 value) external {
        assembly {
            tstore(slot, value)
        }
    }
}

/// @notice Helper to probe tstore support by attempting a tload
contract TstoreGetter {
    function get(bytes32 slot) external view returns (uint256 value) {
        assembly {
            value := tload(slot)
        }
    }
}

// ----------------------------------------------------------------------------
// Mode Toggle Helpers (uses cheatcodes)
// ----------------------------------------------------------------------------

library TstoreMode {
    bytes32 private constant SLOT_TSTORE_SUPPORT = bytes32(uint256(0));

    /// @notice Force-enable Tstorish tstore mode by setting `_tstoreSupport` to true at slot 0
    function setActive(address target) internal {
        HEVM.store(target, SLOT_TSTORE_SUPPORT, bytes32(uint256(1)));
    }

    /// @notice Force-disable Tstorish tstore mode by setting `_tstoreSupport` to false at slot 0
    function setInactive(address target) internal {
        HEVM.store(target, SLOT_TSTORE_SUPPORT, bytes32(uint256(0)));
    }
}

// ----------------------------------------------------------------------------
// tload Utility (etch-based reader)
// ----------------------------------------------------------------------------

/// @notice Utilities to read a transient storage slot from an arbitrary address by
///         temporarily etching `TstoreGetter` bytecode at the target, performing
///         a staticcall, and restoring the original code.
library TstoreRead {
    /// @dev Reads a transient storage value at `slot` from `target` using tload semantics.
    ///      This function preserves and restores the original code at `target`.
    /// @param target The address whose transient storage slot to read.
    /// @param slot The transient storage slot to read.
    /// @return value The uint256 value read from the transient storage slot.
    function tloadAt(address target, bytes32 slot) internal returns (uint256 value) {
        bytes memory originalCode = target.code;

        // Temporarily etch the TstoreGetter runtime code to enable tload via staticcall
        HEVM.etch(target, type(TstoreGetter).runtimeCode);

        (bool ok, bytes memory ret) = target.staticcall(abi.encodeWithSelector(TstoreGetter.get.selector, slot));

        // Restore original code regardless of call outcome
        HEVM.etch(target, originalCode);

        require(ok, "tload failed");
        require(ret.length >= 32, "tload returned insufficient data");

        return abi.decode(ret, (uint256));
    }
}
