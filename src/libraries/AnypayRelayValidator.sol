// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {ECDSA} from "solady/utils/ECDSA.sol";
import {AnypayRelayInfo} from "@/interfaces/AnypayRelay.sol";
import {AnypayRelayDecoder} from "@/libraries/AnypayRelayDecoder.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {console} from "forge-std/console.sol";

/**
 * @title AnypayRelayValidator
 * @author Shun Kakinoki
 * @notice Library for validating Anypay Relay data.
 */
library AnypayRelayValidator {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------

    using ECDSA for bytes32;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    address public constant RELAY_APPROVAL_PROXY = 0xaaaaaaae92Cc1cEeF79a038017889fDd26D23D4d;
    address public constant RELAY_RECEIVER = 0xa5F565650890fBA1824Ee0F21EbBbF660a179934;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error InvalidAttestation();
    error InvalidRelayQuote();

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Validates if the recipient of a relay call is the designated relay solver.
     * @dev This function decodes the relay calldata from a `Payload.Call` struct to determine
     *      the ultimate receiver of the assets (either native or ERC20) and checks if it
     *      matches the provided `relaySolver` address.
     * @param call The `Payload.Call` struct representing a single transaction in the payload.
     * @param relaySolver The address of the authorized relay solver.
     * @return True if the recipient is the `relaySolver`, false otherwise.
     */
    function isValidRelayRecipient(Payload.Call memory call, address relaySolver) internal pure returns (bool) {
        AnypayRelayDecoder.DecodedRelayData memory decodedData = AnypayRelayDecoder.decodeRelayCalldataForSapient(call);
        return decodedData.receiver == relaySolver || decodedData.receiver == RELAY_APPROVAL_PROXY
            || decodedData.receiver == RELAY_RECEIVER;
    }

    /**
     * @notice Validates an array of relay calls to ensure all are sent to the relay solver.
     * @dev Iterates through an array of `Payload.Call` structs and uses `isValidRelayRecipient`
     *      to verify each one. The function returns false if the array is empty.
     * @param calls The array of `Payload.Call` structs to validate.
     * @param relaySolver The address of the authorized relay solver.
     * @return True if all calls are to the `relaySolver`, false otherwise.
     */
    function areValidRelayRecipients(Payload.Call[] memory calls, address relaySolver) internal pure returns (bool) {
        if (calls.length == 0) {
            return false;
        }
        for (uint256 i = 0; i < calls.length; i++) {
            if (!isValidRelayRecipient(calls[i], relaySolver)) {
                return false;
            }
        }
        return true;
    }
}
