// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {TrailsRelayDecoder} from "@/libraries/TrailsRelayDecoder.sol";
import {TrailsExecutionInfo} from "@/interfaces/TrailsExecutionInfo.sol";
import {TrailsRelayInfo} from "@/interfaces/TrailsRelay.sol";
import {TrailsRelayValidator} from "@/libraries/TrailsRelayValidator.sol";
import {TrailsRelayInterpreter} from "@/libraries/TrailsRelayInterpreter.sol";
import {TrailsExecutionInfoParams} from "@/libraries/TrailsExecutionInfoParams.sol";

/**
 * @title TrailsRelaySapientSigner
 * @author Shun Kakinoki
 * @notice An SapientSigner module for Sequence v3 wallets, designed to facilitate relay actions
 *         through the sapient signer module. It validates off-chain attestations to authorize
 *         operations on a specific Relay Facet contract. This enables relayers to execute
 *         relays as per user-attested parameters, without direct wallet pre-approval for each transaction.
 */
contract TrailsRelaySapientSigner is ISapient {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------

    using Payload for Payload.Decoded;
    using TrailsRelayInterpreter for Payload.Call[];
    using TrailsRelayValidator for TrailsRelayDecoder.DecodedRelayData[];
    using TrailsExecutionInfoParams for TrailsExecutionInfo[];
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error InvalidTargetAddress(address expectedTarget, address actualTarget);
    error InvalidAttestation();
    error InvalidCallsLength();
    error InvalidPayloadKind();
    error InvalidRelayRecipient();
    error InvalidAttestationSigner(address expectedSigner, address actualSigner);

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

        // 3. Decode the signature to get execution details and the attestation.
        (TrailsExecutionInfo[] memory executionInfos, bytes memory attestationSignature, address attestationSigner) =
            decodeSignature(encodedSignature);

        // 4. Recover the signer from the attestation signature
        address recoveredAttestationSigner =
            payload.hashFor(address(0)).toEthSignedMessageHash().recover(attestationSignature);

        // 5. Validate the attestation signer
        if (recoveredAttestationSigner != attestationSigner) {
            revert InvalidAttestationSigner(attestationSigner, recoveredAttestationSigner);
        }

        // 6. Construct the digest for attestation.
        bytes32 digest = executionInfos.getTrailsExecutionInfoHash(attestationSigner);

        return digest;
    }

    // -------------------------------------------------------------------------
    // Internal Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Decodes a combined signature into Relay information and the attestation signature.
     * @dev Assumes _signature is abi.encode(TrailsExecutionInfo[] memory, bytes memory, address).
     * @param _signature The combined signature bytes.
     * @return _executionInfos Array of TrailsExecutionInfo structs.
     * @return _attestationSignature The ECDSA signature for attestation.
     * @return _attestationSigner The address of the signer.
     */
    function decodeSignature(bytes calldata _signature)
        public
        pure
        returns (
            TrailsExecutionInfo[] memory _executionInfos,
            bytes memory _attestationSignature,
            address _attestationSigner
        )
    {
        (_executionInfos, _attestationSignature, _attestationSigner) =
            abi.decode(_signature, (TrailsExecutionInfo[], bytes, address));
    }
}
