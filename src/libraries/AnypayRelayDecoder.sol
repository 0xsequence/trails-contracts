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
     * @notice Decodes the relay calldata.
     * @dev The function distinguishes between a native asset transfer and an ERC20 transfer
     *      based on the calldata length.
     *      - For native asset (ETH): expects 32 bytes of calldata (the requestId).
     *        The amount is `msg.value` and the receiver is `msg.sender`. The token is address(0).
     *      - For ERC20 token: expects 100 bytes for a non-standard transfer call
     *        (4-byte selector + 32-byte receiver + 32-byte amount + 32-byte requestId).
     *        The token address is `address(this)`.
     * @param data The calldata to decode (`msg.data`).
     * @return decodedData A struct containing the decoded information.
     */
    function decodeRelayCalldata(bytes calldata data) internal view returns (DecodedRelayData memory decodedData) {
        if (data.length == 32) {
            // Native asset transfer
            decodedData.requestId = abi.decode(data, (bytes32));
            decodedData.token = address(0); // Native asset
            decodedData.amount = msg.value;
            decodedData.receiver = msg.sender; // The contract that initiated the call with value
        } else if (data.length == 100) {
            // ERC20 transfer with appended requestId
            // Expected format: transfer(address,uint256) + requestId
            // 0xa9059cbb - transfer(address,uint256)
            bytes4 selector = bytes4(data[0:4]);
            if (selector == 0xa9059cbb) {
                address receiver = abi.decode(data[4:36], (address));
                uint256 amount = abi.decode(data[36:68], (uint256));
                bytes32 requestId = abi.decode(data[68:100], (bytes32));

                decodedData.requestId = requestId;
                decodedData.token = address(this);
                decodedData.amount = amount;
                decodedData.receiver = receiver;
            } else {
                revert InvalidCalldataLength();
            }
        } else {
            revert InvalidCalldataLength();
        }
    }

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
}
