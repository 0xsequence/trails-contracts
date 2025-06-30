// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {AnypayLiFiFlagDecoder} from "@/libraries/AnypayLiFiFlagDecoder.sol";
import {AnypayLiFiInterpreter} from "@/libraries/AnypayLiFiInterpreter.sol";
import {AnypayExecutionInfoInterpreter, AnypayExecutionInfo} from "@/libraries/AnypayExecutionInfoInterpreter.sol";
import {AnypayExecutionInfoParams} from "@/libraries/AnypayExecutionInfoParams.sol";
import {AnypayDecodingStrategy} from "@/interfaces/AnypayLiFi.sol";

/**
 * @title AnypayLiFiSapientSigner
 * @author Shun Kakinoki
 * @notice An SapientSigner module for Sequence v3 wallets, designed to facilitate LiFi actions
 *         through the sapient signer module. It validates off-chain attestations to authorize
 *         operations on a specific LiFi Diamond contract. This enables relayers to execute LiFi
 *         swaps/bridges as per user-attested parameters, without direct wallet pre-approval for each transaction.
 */
contract AnypayLiFiSapientSigner is ISapient {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------

    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using Payload for Payload.Decoded;
    using AnypayLiFiFlagDecoder for bytes;
    using AnypayLiFiInterpreter for ILiFi.BridgeData;
    using AnypayLiFiInterpreter for AnypayExecutionInfo[];
    using AnypayExecutionInfoInterpreter for AnypayExecutionInfo[];
    using AnypayExecutionInfoParams for AnypayExecutionInfo[];

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    address public immutable TARGET_LIFI_DIAMOND;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error InvalidTargetAddress(address expectedTarget, address actualTarget);
    error InvalidCallsLength();
    error InvalidPayloadKind();
    error InvalidLifiDiamondAddress();
    error InvalidAttestationSigner(address expectedSigner, address actualSigner);
    error InvalidAttestation();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _lifiDiamondAddress) {
        if (_lifiDiamondAddress == address(0)) {
            revert InvalidLifiDiamondAddress();
        }
        TARGET_LIFI_DIAMOND = _lifiDiamondAddress;
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
        if (payload.kind != Payload.KIND_TRANSACTIONS) {
            revert InvalidPayloadKind();
        }

        // 2. Validate inner Payload
        if (payload.calls.length == 0) {
            revert InvalidCallsLength();
        }

        // 3. Verify target address and applicationData matches _lifiCall
        for (uint256 i = 0; i < payload.calls.length; i++) {
            Payload.Call memory call = payload.calls[i];
            if (call.to != TARGET_LIFI_DIAMOND) {
                revert InvalidTargetAddress(TARGET_LIFI_DIAMOND, call.to);
            }
        }

        // 4. Decode the signature
        (
            AnypayExecutionInfo[] memory attestationExecutionInfos,
            AnypayDecodingStrategy decodingStrategy,
            bytes memory attestationSignature,
            address attestationSigner
        ) = decodeSignature(encodedSignature);

        // 5. Recover the signer from the attestation signature
        address recoveredAttestationSigner =
            payload.hashFor(address(0)).toEthSignedMessageHash().recover(attestationSignature);

        // 6. Validate the attestation signer
        if (recoveredAttestationSigner != attestationSigner) {
            revert InvalidAttestationSigner(attestationSigner, recoveredAttestationSigner);
        }

        // 7. Initialize structs to store decoded data
        AnypayExecutionInfo[] memory inferredExecutionInfos = new AnypayExecutionInfo[](payload.calls.length);

        // 8. Decode BridgeData and SwapData from calldata using the library
        for (uint256 i = 0; i < payload.calls.length; i++) {
            (ILiFi.BridgeData memory bridgeData, LibSwap.SwapData[] memory swapData) =
                payload.calls[i].data.decodeLiFiDataOrRevert(decodingStrategy);

            inferredExecutionInfos[i] = bridgeData.getOriginSwapInfo(swapData);
        }

        // 9. Validate the attestations
        if (!inferredExecutionInfos.validateExecutionInfos(attestationExecutionInfos)) {
            revert InvalidAttestation();
        }

        // 10. Hash the lifi intent params
        bytes32 lifiIntentHash = attestationExecutionInfos.getAnypayExecutionInfoHash(attestationSigner);

        return lifiIntentHash;
    }

    // -------------------------------------------------------------------------
    // Internal Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Decodes a combined signature into LiFi information and the attestation signature.
     * @dev Assumes _signature is abi.encode(AnypayExecutionInfo[] memory, bytes memory).
     * @param _signature The combined signature bytes.
     * @return _executionInfos Array of AnypayExecutionInfo structs.
     * @return _decodingStrategy The decoding strategy used.
     * @return _attestationSignature The ECDSA signature for attestation.
     */
    function decodeSignature(bytes calldata _signature)
        public
        pure
        returns (
            AnypayExecutionInfo[] memory _executionInfos,
            AnypayDecodingStrategy _decodingStrategy,
            bytes memory _attestationSignature,
            address _attestationSigner
        )
    {
        (_executionInfos, _decodingStrategy, _attestationSignature, _attestationSigner) =
            abi.decode(_signature, (AnypayExecutionInfo[], AnypayDecodingStrategy, bytes, address));
    }
}
