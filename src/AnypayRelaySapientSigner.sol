// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {AnypayRelayInfo} from "./interfaces/AnypayRelay.sol";
import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";

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
    // Structs
    // -------------------------------------------------------------------------

    /// @dev Relay specific parameters from RelayFacet
    struct RelayData {
        bytes32 requestId;
        bytes32 nonEVMReceiver;
        bytes32 receivingAssetId;
        bytes signature;
    }

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    address public immutable RELAY_SOLVER;
    address public constant NON_EVM_ADDRESS = 0x11f111f111f111F111f111f111F111f111f111F1;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error InvalidTargetAddress(address expectedTarget, address actualTarget);
    error InvalidCallsLength();
    error InvalidPayloadKind();
    error InvalidRelaySolverAddress();
    error InvalidAttestationSigner(address expectedSigner, address actualSigner);
    error InvalidAttestation();
    error InvalidCalldata();
    error MismatchedRelayInfoLengths();
    error InvalidRelayQuote();
    error NoMatchingInferredInfoFound(bytes32 requestId);
    error InferredAmountTooHigh(uint256 inferredAmount, uint256 attestedAmount);

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
        // 1. Decode the signature
        (bytes memory attestationSignature, AnypayRelayInfo[] memory attestedRelayInfos) =
            decodeSignature(encodedSignature);

        // 2. Recover the signer from the attestation signature
        address recoveredAttestationSigner =
            keccak256(abi.encode(payload.hashFor(address(0)))).recover(attestationSignature);

        if (recoveredAttestationSigner == address(0)) {
            revert InvalidAttestationSigner(address(0), recoveredAttestationSigner);
        }

        // 3. Validate attestations
        if (!_validateRelayInfos(attestedRelayInfos)) {
            revert InvalidAttestation();
        }

        // 4. Hash the relay intent params
        bytes32 relayIntentHash = keccak256(abi.encode(attestedRelayInfos, recoveredAttestationSigner));

        return relayIntentHash;
    }

    // -------------------------------------------------------------------------
    // Internal Functions
    // -------------------------------------------------------------------------

    function _validateRelayInfos(AnypayRelayInfo[] memory attestedRelayInfos) internal view returns (bool) {
        if (attestedRelayInfos.length == 0) {
            revert MismatchedRelayInfoLengths();
        }

        uint256 numInfos = attestedRelayInfos.length;

        for (uint256 i = 0; i < numInfos; i++) {
            AnypayRelayInfo memory attestedInfo = attestedRelayInfos[i];

            // Check relay solver signature
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

            address signer = message.recover(attestedInfo.signature);
            if (signer != RELAY_SOLVER) {
                revert InvalidRelayQuote();
            }
        }

        return true;
    }

    /**
     * @notice Decodes a combined signature into Relay information and the attestation signature.
     * @dev Assumes _signature is abi.encode(bytes memory, AnypayRelayInfo[] memory).
     * @param _signature The combined signature bytes.
     * @return _attestationSignature The ECDSA signature for attestation.
     * @return _relayInfos Array of AnypayRelayInfo structs.
     */
    function decodeSignature(bytes calldata _signature)
        public
        pure
        returns (bytes memory _attestationSignature, AnypayRelayInfo[] memory _relayInfos)
    {
        (_attestationSignature, _relayInfos) = abi.decode(_signature, (bytes, AnypayRelayInfo[]));
    }
} 
