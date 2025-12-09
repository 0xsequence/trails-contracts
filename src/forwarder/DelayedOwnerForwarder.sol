// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title DelayedOwnerForwarder
/// @author Michael Standen
/// @notice A forwarder that derives ownership from the first caller.
contract DelayedOwnerForwarder {
    error NotCalledByOwner();
    error InvalidCallData();
    error ForwardFailed();

    /// @notice Owner of the forwarder
    /// @dev Set to the first caller if not already set
    address public owner;

    constructor() payable {}

    modifier checkSetOwner() {
        if (owner == address(0)) {
            owner = msg.sender;
        } else if (msg.sender != owner) {
            revert NotCalledByOwner();
        }
        _;
    }

    /// @notice Call a function
    /// @dev Sets owner if not already set
    /// @dev If owner is set, must be called by owner
    /// @param to The address to call
    /// @param data The data to call
    function call(address to, bytes memory data) external payable checkSetOwner {
        // Forward the call
        (bool success,) = to.call{value: msg.value}(data);
        if (!success) {
            revert ForwardFailed();
        }
    }

    /// @notice Delegatecall a function
    /// @dev Sets owner if not already set
    /// @dev If owner is set, must be called by owner
    /// @param to The address to delegatecall
    /// @param data The data to delegatecall
    function delegatecall(address to, bytes memory data) external payable checkSetOwner {
        (bool success,) = to.delegatecall(data);
        if (!success) {
            revert ForwardFailed();
        }
    }
}
