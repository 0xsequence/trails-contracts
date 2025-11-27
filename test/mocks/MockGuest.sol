// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

/// @notice Mock Guest module for testing
/// @dev Implements fallback that accepts CallsPayload format
contract MockGuest {
    bool public shouldFail;

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    /// @notice Receive ETH
    receive() external payable {}

    /// @notice Fallback function that accepts CallsPayload encoded data
    /// @dev Mimics Guest module's fallback behavior
    fallback() external payable {
        if (shouldFail) {
            revert("MockGuest: forced failure");
        }

        // Decode CallsPayload
        Payload.Decoded memory decoded = Payload.fromPackedCalls(msg.data);

        // Execute calls
        for (uint256 i = 0; i < decoded.calls.length; i++) {
            Payload.Call memory call = decoded.calls[i];

            // Skip onlyFallback calls
            if (call.onlyFallback) {
                continue;
            }

            // Execute call
            uint256 gasLimit = call.gasLimit == 0 ? gasleft() : call.gasLimit;
            (bool success,) = call.to.call{value: call.value, gas: gasLimit}(call.data);

            if (!success) {
                if (call.behaviorOnError == Payload.BEHAVIOR_REVERT_ON_ERROR) {
                    revert("MockGuest: call failed");
                } else if (call.behaviorOnError == Payload.BEHAVIOR_ABORT_ON_ERROR) {
                    break;
                }
                // BEHAVIOR_IGNORE_ERROR: continue execution
            }
        }
    }
}

