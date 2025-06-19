// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

/**
 * @title AnypayRelayDecoder
 * @author Your Name
 * @notice Library to decode calldata for Anypay Relay operations.
 */
library AnypayRelayDecoder {
    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    struct DecodedRelayData {
        bytes32 requestId;
        address token;
        uint256 amount;
        address receiver;
    }

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error InvalidCalldataLength();

    // -------------------------------------------------------------------------
    // Decoding Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Decodes the relay calldata for the AnypayRelaySapientSigner.
     * @dev This version of the decoder is specifically for use within the SapientSigner,
     *      which receives the transaction details within a `Payload.Call` struct.
     * @param call The `Payload.Call` struct containing transaction details (to, value, data).
     * @return decodedData A struct containing the decoded information.
     */
    function decodeRelayCalldataForSapient(Payload.Call memory call)
        internal
        pure
        returns (DecodedRelayData memory decodedData)
    {
        if (call.data.length == 32) {
            // Native asset transfer
            decodedData.requestId = abi.decode(call.data, (bytes32));
            decodedData.token = address(0); // Native asset
            decodedData.amount = call.value;
            decodedData.receiver = call.to; // The receiver of the native asset is the target of the call
        } else if (call.data.length == 100) {
            bytes memory data = call.data;
            bytes32 selector;
            uint256 receiverWord;
            uint256 amount;
            bytes32 requestId;

            assembly {
                let d := add(data, 0x20)
                selector := mload(d)
                receiverWord := mload(add(d, 4))
                amount := mload(add(d, 36))
                requestId := mload(add(d, 68))
            }

            if (bytes4(selector) == 0xa9059cbb) {
                decodedData.requestId = requestId;
                decodedData.token = call.to;
                decodedData.amount = amount;
                decodedData.receiver = address(uint160(receiverWord));
            } else {
                revert InvalidCalldataLength();
            }
        } else {
            revert InvalidCalldataLength();
        }
    }

    /**
     * @notice Extracts the requestId from relay calldata.
     * @dev This function supports both native asset transfers (32-byte calldata for requestId)
     *      and ERC20 transfers (100-byte calldata with requestId appended).
     * @param data The calldata from a `Payload.Call` struct.
     * @return requestId The extracted requestId.
     */
    function getRequestId(bytes memory data) internal pure returns (bytes32 requestId) {
        if (data.length == 32) {
            // Native asset transfer
            requestId = abi.decode(data, (bytes32));
        } else if (data.length == 100) {
            bytes32 selector;
            bytes32 _requestId;

            assembly {
                let d := add(data, 0x20)
                selector := mload(d)
                _requestId := mload(add(d, 68))
            }

            if (bytes4(selector) == 0xa9059cbb) {
                requestId = _requestId;
            } else {
                revert InvalidCalldataLength();
            }
        } else {
            revert InvalidCalldataLength();
        }
    }

    /**
     * @notice Extracts all requestIds from an array of relay calls.
     * @dev Iterates through an array of `Payload.Call` structs and uses `getRequestId`
     *      to extract the requestId from each.
     * @param calls The array of `Payload.Call` structs.
     * @return requestIds An array of extracted requestIds.
     */
    function getRequestIds(Payload.Call[] memory calls) internal pure returns (bytes32[] memory requestIds) {
        requestIds = new bytes32[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            requestIds[i] = getRequestId(calls[i].data);
        }
    }
}
