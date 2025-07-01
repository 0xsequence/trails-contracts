// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {AnypayRelayDecoder} from "@/libraries/AnypayRelayDecoder.sol";
import {AnypayExecutionInfo} from "@/interfaces/AnypayExecutionInfo.sol";
import {AnypayRelayInfo} from "@/interfaces/AnypayRelay.sol";
import {AnypayRelayValidator} from "@/libraries/AnypayRelayValidator.sol";
import {AnypayRelayInterpreter} from "@/libraries/AnypayRelayInterpreter.sol";
import {AnypayExecutionInfoParams} from "@/libraries/AnypayExecutionInfoParams.sol";

/**
 * @title AnypayRelaySapientSigner
 * @author Shun Kakinoki
 * @notice An SapientSigner module for Sequence v3 wallets, designed to facilitate relay actions
 *         through the sapient signer module. It validates off-chain attestations to authorize
 *         operations on a specific Relay Facet contract. This enables relayers to execute
 *         relays as per user-attested parameters, without direct wallet pre-approval for each transaction.
 */
contract AnypayRelaySapientSigner is ISapient {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------

    using Payload for Payload.Decoded;
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;
    using AnypayExecutionInfoParams for AnypayExecutionInfo[];
    using AnypayRelayValidator for AnypayExecutionInfo;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error InvalidTargetAddress(address expectedTarget, address actualTarget);
    error InvalidAttestation();
    error InvalidCallsLength();
    error InvalidPayloadKind();
    error InvalidRelayRecipient();
    error InvalidAttestationSigner(address expectedSigner, address actualSigner);
    error MismatchedRelayInfoLengths();

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /// @inheritdoc ISapient
    function recoverSapientSignature(Payload.Decoded calldata payload, bytes calldata encodedSignature)
        external
        view
        returns (bytes32)
    {
        // 1. Validate outer Payload
        if (payload.kind != Payload.KIND_TRANSACTIONS) {
            revert InvalidPayloadKind();
        }

        // 2. Validate inner Payload
        if (payload.calls.length == 0) {
            revert InvalidCallsLength();
        }

        // 3. Validate relay recipients
        if (!AnypayRelayValidator.areValidRelayRecipients(payload.calls)) {
            revert InvalidRelayRecipient();
        }

        // 4. Decode the signature to get execution details and the attestation.
        (AnypayExecutionInfo[] memory executionInfos, bytes memory attestationSignature, address attestationSigner) =
            decodeSignature(encodedSignature);

        // 5. Recover the signer from the attestation signature
        address recoveredAttestationSigner =
            payload.hashFor(address(0)).toEthSignedMessageHash().recover(attestationSignature);

        // 6. Validate the attestation signer
        if (recoveredAttestationSigner != attestationSigner) {
            revert InvalidAttestationSigner(attestationSigner, recoveredAttestationSigner);
        }

        // 7. Construct the digest for attestation.
        bytes32 digest = executionInfos.getAnypayExecutionInfoHash(attestationSigner);

        // TODO: Uncomment this when we have a way to validate the attestations against the inferred relay information
        // // 8. Decode all relay calls to get inferred relay information
        // AnypayRelayDecoder.DecodedRelayData[] memory inferredRelayData =
        //     new AnypayRelayDecoder.DecodedRelayData[](payload.calls.length);
        // for (uint256 i = 0; i < payload.calls.length; i++) {
        //     inferredRelayData[i] = AnypayRelayDecoder.decodeRelayCalldataForSapient(payload.calls[i]);
        // }

        // // 9. Validate the attestations against the inferred relay information
        // if (!AnypayRelayInterpreter.validateRelayInfos(inferredRelayData, executionInfos)) {
        //     revert InvalidAttestation();
        // }

        return digest;
    }

    // -------------------------------------------------------------------------
    // Internal Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Decodes a combined signature into Relay information and the attestation signature.
     * @dev Assumes _signature is abi.encode(AnypayExecutionInfo[] memory, bytes memory, address).
     * @param _signature The combined signature bytes.
     * @return _executionInfos Array of AnypayExecutionInfo structs.
     * @return _attestationSignature The ECDSA signature for attestation.
     * @return _attestationSigner The address of the signer.
     */
    function decodeSignature(bytes calldata _signature)
        public
        pure
        returns (
            AnypayExecutionInfo[] memory _executionInfos,
            bytes memory _attestationSignature,
            address _attestationSigner
        )
    {
        (_executionInfos, _attestationSignature, _attestationSigner) =
            abi.decode(_signature, (AnypayExecutionInfo[], bytes, address));
    }
}
