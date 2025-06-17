// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {ECDSA} from "solady/utils/ECDSA.sol";
import {AnypayRelayInfo} from "@/interfaces/AnypayRelay.sol";
import {AnypayRelayDecoder} from "@/libraries/AnypayRelayDecoder.sol";

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
    // Errors
    // -------------------------------------------------------------------------

    error InvalidAttestation();
    error InvalidRelayQuote();

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    address public constant NON_EVM_ADDRESS = 0x1111111111111111111111111111111111111111;

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Validates the relay parameters and checks the relay solver's signature.
     * @param attestedInfo The attested relay information from the signature.
     * @param inferredInfo The inferred relay information from the transaction calldata.
     * @param relaySolver The address of the relay solver.
     */
    function validateRelayInfo(
        AnypayRelayInfo memory attestedInfo,
        AnypayRelayDecoder.DecodedRelayData memory inferredInfo,
        address relaySolver
    ) internal view {
        // a. Validate relay parameters
        if (
            inferredInfo.requestId != attestedInfo.requestId || inferredInfo.token != attestedInfo.sendingAssetId
                || inferredInfo.receiver != attestedInfo.receiver || inferredInfo.amount < attestedInfo.minAmount
        ) {
            revert InvalidAttestation();
        }

        // b. Check relay solver signature
        bytes32 message = keccak256(
            abi.encodePacked(
                attestedInfo.requestId,
                block.chainid,
                bytes32(uint256(uint160(attestedInfo.target))),
                bytes32(uint256(uint160(attestedInfo.sendingAssetId))),
                attestedInfo.destinationChainId,
                attestedInfo.receiver == NON_EVM_ADDRESS
                    ? attestedInfo.nonEVMReceiver : bytes32(uint256(uint160(attestedInfo.receiver))),
                attestedInfo.receivingAssetId,
                attestedInfo.minAmount
            )
        );

        bytes32 digest = ECDSA.toEthSignedMessageHash(message);
        address signer = ECDSA.recover(digest, attestedInfo.signature);

        if (signer != relaySolver) {
            revert InvalidRelayQuote();
        }
    }
} 