// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {AnypayRelayInfo} from "@/interfaces/AnypayRelay.sol";
import {AnypayRelayDecoder} from "@/libraries/AnypayRelayDecoder.sol";

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
    using ECDSA for bytes32;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    address public immutable RELAY_SOLVER;
    address public constant NON_EVM_ADDRESS = 0x1111111111111111111111111111111111111111;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error InvalidTargetAddress(address expectedTarget, address actualTarget);
    error InvalidCallsLength();
    error InvalidPayloadKind();
    error InvalidRelaySolverAddress();
    error InvalidAttestationSigner(address expectedSigner, address actualSigner);
    error InvalidAttestation();
    error MismatchedRelayInfoLengths();
    error InvalidRelayQuote();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _relaySolver) {
        if (_relaySolver == address(0)) {
            revert InvalidRelaySolverAddress();
        }
        RELAY_SOLVER = _relaySolver;
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
        return _recoverSapientSignature(msg.sender, payload, encodedSignature);
    }

    /**
     * @notice Recovers the root hash of a given signature with wallet context.
     * @param _wallet The address of the wallet.
     * @param payload The decoded payload.
     * @param encodedSignature The encoded signature.
     * @return The hash of the relay intent parameters.
     */
    function _recoverSapientSignature(
        address _wallet,
        Payload.Decoded calldata payload,
        bytes calldata encodedSignature
    ) internal view returns (bytes32) {
        // 1. Validate outer Payload
        if (payload.kind != Payload.KIND_TRANSACTIONS) {
            revert InvalidPayloadKind();
        }

        // 2. Validate inner Payload
        if (payload.calls.length == 0) {
            revert InvalidCallsLength();
        }

        // 3. Decode the signature
        (AnypayRelayInfo[] memory attestedRelayInfos, bytes memory attestationSignature, address attestationSigner) =
            decodeSignature(encodedSignature);

        // 4. Check that calls and relay infos have the same length
        if (payload.calls.length != attestedRelayInfos.length) {
            revert MismatchedRelayInfoLengths();
        }

        // 5. Recover the signer from the attestation signature
        address recoveredAttestationSigner = payload.hashFor(_wallet).recover(attestationSignature);
        if (recoveredAttestationSigner != attestationSigner) {
            revert InvalidAttestationSigner(attestationSigner, recoveredAttestationSigner);
        }

        // 6. Validate attestations and compare with inferred data
        for (uint256 i = 0; i < payload.calls.length; i++) {
            Payload.Call memory call = payload.calls[i];
            AnypayRelayInfo memory attestedInfo = attestedRelayInfos[i];
            AnypayRelayDecoder.DecodedRelayData memory inferredInfo =
                AnypayRelayDecoder.decodeRelayCalldataForSapient(call);

            // a. Validate relay parameters
            if (inferredInfo.requestId != attestedInfo.requestId || inferredInfo.token != attestedInfo.sendingAssetId
                || inferredInfo.receiver != attestedInfo.receiver) {
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
                        ? attestedInfo.nonEVMReceiver
                        : bytes32(uint256(uint160(attestedInfo.receiver))),
                    attestedInfo.receivingAssetId
                )
            );

            address signer =
                keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message)).recover(attestedInfo.signature);
            if (signer != RELAY_SOLVER) {
                revert InvalidRelayQuote();
            }
        }

        // 7. Hash the relay intent params
        bytes32 relayIntentHash = keccak256(abi.encode(attestedRelayInfos, attestationSigner));

        return relayIntentHash;
    }

    // -------------------------------------------------------------------------
    // Internal Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Decodes a combined signature into Relay information and the attestation signature.
     * @dev Assumes _signature is abi.encode(AnypayRelayInfo[] memory, bytes memory, address).
     * @param _signature The combined signature bytes.
     * @return _relayInfos Array of AnypayRelayInfo structs.
     * @return _attestationSignature The ECDSA signature for attestation.
     * @return _attestationSigner The address of the signer.
     */
    function decodeSignature(bytes calldata _signature)
        public
        pure
        returns (
            AnypayRelayInfo[] memory _relayInfos,
            bytes memory _attestationSignature,
            address _attestationSigner
        )
    {
        (_relayInfos, _attestationSignature, _attestationSigner) =
            abi.decode(_signature, (AnypayRelayInfo[], bytes, address));
    }
}
