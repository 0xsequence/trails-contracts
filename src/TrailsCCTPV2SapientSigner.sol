// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {TrailsExecutionInfo} from "@/interfaces/TrailsExecutionInfo.sol";
import {TrailsCCTPV2Interpreter} from "@/libraries/TrailsCCTPV2Interpreter.sol";
import {TrailsExecutionInfoInterpreter} from "@/libraries/TrailsExecutionInfoInterpreter.sol";
import {TrailsExecutionInfoParams} from "@/libraries/TrailsExecutionInfoParams.sol";

/**
 * @title TrailsCCTPV2SapientSigner
 * @author Shun Kakinoki
 * @notice An SapientSigner module for Sequence v3 wallets, designed to facilitate Circle CCTP V2 actions
 *         through the sapient signer module. It validates off-chain attestations to authorize
 *         operations on a specific TokenMessengerV2 contract. This enables relayers to execute CCTP
 *         burn-and-mint operations as per user-attested parameters, without direct wallet pre-approval.
 */
contract TrailsCCTPV2SapientSigner is ISapient {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------

    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using Payload for Payload.Decoded;
    using TrailsCCTPV2Interpreter for Payload.Call[];
    using TrailsExecutionInfoInterpreter for TrailsExecutionInfo[];
    using TrailsExecutionInfoParams for TrailsExecutionInfo[];

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    address public immutable TARGET_TOKEN_MESSENGER;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error InvalidTargetAddress(address expectedTarget, address actualTarget);
    error InvalidCallsLength();
    error InvalidPayloadKind();
    error InvalidTokenMessengerAddress();
    error InvalidAttestationSigner(address expectedSigner, address actualSigner);
    error InvalidAttestation();
    error InvalidCalldata();
    error MismatchedAttestationLength();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _tokenMessengerAddress) {
        if (_tokenMessengerAddress == address(0)) {
            revert InvalidTokenMessengerAddress();
        }
        TARGET_TOKEN_MESSENGER = _tokenMessengerAddress;
    }

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
        if (payload.kind != Payload.KIND_TRANSACTIONS) revert InvalidPayloadKind();
        if (payload.calls.length == 0) revert InvalidCallsLength();

        // 2. Verify target address for all calls
        for (uint256 i = 0; i < payload.calls.length; i++) {
            if (payload.calls[i].to != TARGET_TOKEN_MESSENGER) {
                revert InvalidTargetAddress(TARGET_TOKEN_MESSENGER, payload.calls[i].to);
            }
        }

        // 3. Decode the signature
        (
            TrailsExecutionInfo[] memory attestationExecutionInfos,
            bytes memory attestationSignature,
            address attestationSigner
        ) = decodeSignature(encodedSignature);

        // 4. Recover the signer from the attestation signature
        address recoveredAttestationSigner =
            payload.hashFor(address(0)).toEthSignedMessageHash().recover(attestationSignature);

        // 5. Validate the attestation signer
        if (recoveredAttestationSigner != attestationSigner) {
            revert InvalidAttestationSigner(attestationSigner, recoveredAttestationSigner);
        }

        // 6. Get inferred execution infos from calldata
        TrailsExecutionInfo[] memory inferredExecutionInfos = payload.calls.getInferredCCTPExecutionInfos();

        // 7. Validate the attestations
        if (!inferredExecutionInfos.validateExecutionInfos(attestationExecutionInfos)) {
            revert InvalidAttestation();
        }

        // 8. Hash the CCTP intent params
        bytes32 cctpIntentHash = attestationExecutionInfos.getTrailsExecutionInfoHash(attestationSigner);

        return cctpIntentHash;
    }

    // -------------------------------------------------------------------------
    // Internal Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Decodes a combined signature into CCTP information and the attestation signature.
     * @param _signature The combined signature bytes.
     * @return _executionInfos Array of TrailsExecutionInfo structs.
     * @return _attestationSignature The ECDSA signature for attestation.
     * @return _attestationSigner The address of the signer for the attestation.
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
