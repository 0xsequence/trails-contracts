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
    // Constants
    // -------------------------------------------------------------------------

    address private constant RELAY_RECEIVER = 0xa5F565650890fBA1824Ee0F21EbBbF660a179934;

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
        if (call.to == RELAY_RECEIVER) {
            if (call.data.length != 64) {
                revert InvalidCalldataLength();
            }

            bytes memory data = call.data;
            bytes32 requestId;
            uint256 receiverWord;

            assembly {
                let d := add(data, 0x20)
                requestId := mload(d)
                receiverWord := mload(add(d, 32))
            }

            decodedData.requestId = requestId;
            decodedData.token = address(0);
            decodedData.amount = call.value;
            decodedData.receiver = address(uint160(receiverWord));
        } else if (call.data.length == 32) {
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
}
