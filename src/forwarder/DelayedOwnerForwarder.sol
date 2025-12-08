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

    /// @notice Fallback function to forward calls
    /// @dev Sets owner if not already set
    /// @dev If owner is set, must be called by owner
    fallback() external payable {
        // Check ownership
        if (owner == address(0)) {
            owner = msg.sender;
        } else if (msg.sender != owner) {
            revert NotCalledByOwner();
        }
        // Forward the call
        if (msg.data.length < 20) {
            revert InvalidCallData();
        }
        address to = address(bytes20(msg.data[0:20]));
        (bool success,) = to.call{value: msg.value}(msg.data[20:]);
        if (!success) {
            revert ForwardFailed();
        }
    }

    /// @notice Receive native tokens
    /// @dev Ignores ownership
    receive() external payable {}
}
