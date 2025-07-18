// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {TrailsRelayConstants} from "@/libraries/TrailsRelayConstants.sol";

/**
 * @title TrailsRelayDecoder
 * @author Your Name
 * @notice Library to decode calldata for Trails Relay operations.
 */
library TrailsRelayDecoder {
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
     * @notice Decodes the relay calldata for the TrailsRelaySapientSigner.
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
        if (call.to == TrailsRelayConstants.RELAY_MULTICALL_PROXY) {
            decodedData.requestId = bytes32(type(uint256).max);
            decodedData.token = address(0);
            decodedData.amount = call.value;
            decodedData.receiver = TrailsRelayConstants.RELAY_MULTICALL_PROXY;
            return decodedData;
        }
        if (call.data.length == 32) {
            // Native asset transfer. This could be to the RelayReceiver contract, which then forwards
            // to the RELAY_SOLVER, or it could be a direct transfer to another address (which should be the solver).
            decodedData.requestId = abi.decode(call.data, (bytes32));
            decodedData.token = address(0);
            decodedData.amount = call.value;
            if (call.to == TrailsRelayConstants.RELAY_RECEIVER) {
                // If the transfer is to the RelayReceiver contract, the ultimate recipient is the RELAY_SOLVER.
                decodedData.receiver = TrailsRelayConstants.RELAY_SOLVER;
            } else {
                // Otherwise, the recipient is the direct target of the call.
                decodedData.receiver = call.to;
            }
        } else if (call.to == TrailsRelayConstants.RELAY_RECEIVER) {
            bytes memory data = call.data;
            if (call.data.length >= 4) {
                bytes4 selector;

                assembly {
                    selector := mload(add(data, 0x20))
                }

                if (selector == 0xd948d468) {
                    // forward(bytes)
                    // Skip selector
                    bytes memory dataToDecode = new bytes(call.data.length - 4);
                    for (uint256 i = 0; i < dataToDecode.length; i++) {
                        dataToDecode[i] = call.data[i + 4];
                    }
                    (bytes memory innerData) = abi.decode(dataToDecode, (bytes));
                    if (innerData.length == 32) {
                        decodedData.requestId = bytes32(innerData);
                        decodedData.token = address(0);
                        decodedData.amount = call.value;
                        decodedData.receiver = TrailsRelayConstants.RELAY_SOLVER;
                        return decodedData;
                    }
                }
            }

            if (call.data.length != 64) {
                revert InvalidCalldataLength();
            }

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
        } else if (call.data.length == 68) {
            bytes4 selector;
            bytes32 spender;
            uint256 amount;
            bytes memory data = call.data;

            assembly {
                let d := add(data, 0x20)
                selector := mload(d)
                spender := mload(add(d, 4))
                amount := mload(add(d, 36))
            }

            // function selector for `approve(address,uint256)`
            if (bytes4(selector) == 0x095ea7b3) {
                decodedData.requestId = bytes32(0);
                decodedData.token = call.to;
                decodedData.amount = amount;
                decodedData.receiver = address(uint160(uint256(spender)));
            } else {
                revert InvalidCalldataLength();
            }
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

            // function selector for `transfer(address,uint256)`
            if (bytes4(selector) == 0xa9059cbb) {
                decodedData.requestId = requestId;
                decodedData.token = call.to;
                decodedData.amount = amount;
                decodedData.receiver = address(uint160(receiverWord));
            } else {
                revert InvalidCalldataLength();
            }
        } else if (call.to == TrailsRelayConstants.RELAY_APPROVAL_PROXY_V2) {
            decodedData.requestId = bytes32(0);
            decodedData.token = call.to;
            decodedData.amount = call.value;
            decodedData.receiver = TrailsRelayConstants.RELAY_SOLVER;
        } else {
            revert InvalidCalldataLength();
        }
    }
}
