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
