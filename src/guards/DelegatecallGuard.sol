// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Abstract contract providing a reusable delegatecall-only guard.
abstract contract DelegatecallGuard {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    /// @dev Error thrown when a function expected to be delegatecalled is invoked directly
    error NotDelegateCall();

    // -------------------------------------------------------------------------
    // Immutable Variables
    // -------------------------------------------------------------------------

    /// @dev Cached address of this contract to detect delegatecall context
    address internal immutable _SELF = address(this);

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    /// @dev Modifier restricting functions to only be executed via delegatecall
    modifier onlyDelegatecall() {
        _onlyDelegatecall();
        _;
    }

    // -------------------------------------------------------------------------
    // Internal Functions
    // -------------------------------------------------------------------------

    /// @dev Internal check enforcing delegatecall context
    function _onlyDelegatecall() internal view {
        if (address(this) == _SELF) revert NotDelegateCall();
    }
}
