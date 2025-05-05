// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title AnypayLifiModifierWrapper
 * @notice WARNING: Highly experimental wrapper for Anypay. Use with extreme caution.
 *         Intercepts ALL calls. Attempts conditional modification (if current receiver=0xFFf...)
 *         assuming offset 228 (likely 2 args), forwards call. If that fails or no modification,
 *         attempts conditional modification assuming offset 260 (likely 3 args), forwards call.
 *         If both modification attempts fail or receiver wasn't 0xFFf..., forwards original calldata.
 * @dev Relies on hardcoded offsets (228, 260) potentially corresponding to different function
 *      signatures where BridgeData memory is the first parameter. See previous comments for details.
 *      Success of internal calls is NOT a guarantee that the correct offset was used or modification occurred.
 */
contract AnypayLifiModifierWrapper {
    // --- Immutables ---

    /// @notice The target LiFi Diamond contract address.
    address public immutable TARGET_LIFI_DIAMOND;

    // --- Constants ---

    /// @notice Assumed offset for func(BridgeData memory, Param2 calldata)
    uint256 internal constant RECEIVER_OFFSET_ASSUMED_2_ARGS = 228;
    /// @notice Assumed offset for func(BridgeData memory, Param2 calldata, Param3 calldata)
    uint256 internal constant RECEIVER_OFFSET_ASSUMED_3_ARGS = 260;

    /// @notice Hardcoded receiver
    address internal constant SENTINEL_RECEIVER = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;

    // --- Events ---
    event ForwardAttempt(uint256 indexed offset, bytes4 selector, address sender, bool modificationMade);
    event ForwardResult(bool success, uint256 indexed usedOffset);

    constructor(address _lifiDiamondAddress) {
        require(_lifiDiamondAddress != address(0), "Wrapper: Zero address");
        TARGET_LIFI_DIAMOND = _lifiDiamondAddress;
    }

    /**
     * @dev Fallback function trying offsets 228, then 260, then unmodified.
     *      Modification only happens if the value at offset is SENTINEL_RECEIVER.
     */
    fallback() external payable {
        uint256 dataSize;
        bool success;
        bytes memory returnData;
        assembly {
            dataSize := calldatasize()
        }
        address sender = msg.sender;
        bytes4 selector = msg.sig;

        bytes memory originalDataCopy = new bytes(dataSize);
        assembly {
            calldatacopy(add(originalDataCopy, 0x20), 0, dataSize)
        }

        // --- Attempt 1: Offset 228 (Assumed 2 Args w/ 1st as ILiFi.BridgeData) ---
        bool attempt1Possible = dataSize >= RECEIVER_OFFSET_ASSUMED_2_ARGS + 32;
        if (attempt1Possible) {
            bytes memory attempt1Data = _cloneBytes(originalDataCopy);
            bool modified1 = _conditionallyModifyData(attempt1Data, RECEIVER_OFFSET_ASSUMED_2_ARGS, sender);
            emit ForwardAttempt(RECEIVER_OFFSET_ASSUMED_2_ARGS, selector, sender, modified1);

            // Only forward this version if modification actually happened
            if (modified1) {
                (success, returnData) = TARGET_LIFI_DIAMOND.call{value: msg.value}(attempt1Data);
                emit ForwardResult(success, RECEIVER_OFFSET_ASSUMED_2_ARGS);
                if (success) {
                    _handleReturnData(success, returnData);
                    return; // Exit fallback
                }
                // If forward failed even after modification, continue to next attempt
            }
            // If not modified, continue to next attempt
        }

        // --- Attempt 2: Offset 260 (Assumed 3 Args w/ 1st as ILiFi.BridgeData) ---
        bool attempt2Possible = dataSize >= RECEIVER_OFFSET_ASSUMED_3_ARGS + 32;
        if (attempt2Possible) {
            bytes memory attempt2Data = _cloneBytes(originalDataCopy);
            // Use new offset
            bool modified2 = _conditionallyModifyData(attempt2Data, RECEIVER_OFFSET_ASSUMED_3_ARGS, sender);
            // Use new offset in event
            emit ForwardAttempt(RECEIVER_OFFSET_ASSUMED_3_ARGS, selector, sender, modified2);

            // Only forward this version if modification actually happened
            if (modified2) {
                // Use new offset in result event
                (success, returnData) = TARGET_LIFI_DIAMOND.call{value: msg.value}(attempt2Data);
                emit ForwardResult(success, RECEIVER_OFFSET_ASSUMED_3_ARGS);
                if (success) {
                    _handleReturnData(success, returnData);
                    return; // Exit fallback
                }
                // If forward failed even after modification, continue to final attempt
            }
            // If not modified, continue to final attempt
        }

        // --- Final Attempt: Unmodified ---
        string memory reason;
        if (!attempt1Possible && !attempt2Possible) {
            // Check both possibilities
            reason = "Calldata too short for modification attempts";
        } else {
            reason = "Modification attempts failed or sentinel not found";
        }
        emit ForwardAttempt(0, selector, sender, false);

        (success, returnData) = TARGET_LIFI_DIAMOND.call{value: msg.value}(originalDataCopy);
        emit ForwardResult(success, 0);

        _handleReturnData(success, returnData);
    }

    /**
     * @dev Helper to conditionally modify bytes in memory at a specific offset.
     *      Only modifies if the current value matches the sentinel address.
     * @return modified True if modification occurred, false otherwise.
     */
    function _conditionallyModifyData(bytes memory data, uint256 offset, address valueToInsert)
        internal
        pure
        returns (bool modified)
    {
        address sentinel = SENTINEL_RECEIVER;
        assembly {
            let ptr := add(data, add(0x20, offset))
            let currentValue := mload(ptr)
            if eq(currentValue, sentinel) {
                mstore(ptr, valueToInsert)
                modified := 1
            }
        }
    }

    /**
     * @dev Helper to clone bytes memory array. (Inefficient, simple version)
     */
    function _cloneBytes(bytes memory original) internal pure returns (bytes memory) {
        bytes memory copy = new bytes(original.length);
        assembly {
            let len := mload(original)
            let src := add(original, 0x20)
            let dest := add(copy, 0x20)
            for { let i := 0 } lt(i, len) { i := add(i, 32) } { mstore(add(dest, i), mload(add(src, i))) }
        }
        return copy;
    }

    /**
     * @dev Handles returning data or reverting based on call success.
     */
    function _handleReturnData(bool success, bytes memory returnData) internal pure {
        if (!success) {
            assembly {
                revert(add(returnData, 0x20), mload(returnData))
            }
        } else {
            assembly {
                return(add(returnData, 0x20), mload(returnData))
            }
        }
    }

    /**
     * @dev Needed to receive plain Ether transfers.
     */
    receive() external payable {}
}
