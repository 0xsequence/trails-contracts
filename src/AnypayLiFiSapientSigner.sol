// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {AnypayLiFiDecoder} from "./libraries/AnypayLiFiDecoder.sol";
import {AnypayLiFiInterpreter, AnypayLifiInfo} from "./libraries/AnypayLiFiInterpreter.sol";
import {AnypayIntentParams} from "./libraries/AnypayIntentParams.sol";
import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";

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

    using Payload for Payload.Decoded;

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
        (AnypayLifiInfo[] memory attestationLifiInfos, bytes memory attestationSignature) =
            _decodeSignature(encodedSignature);

        // 5. Recover the signer from the attestation signature
        address attestationSigner =
            ECDSA.recover(keccak256(abi.encode(payload.hashFor(address(0)))), attestationSignature);

        // 6. Initialize structs to store decoded data
        AnypayLifiInfo[] memory inferredLifiInfos = new AnypayLifiInfo[](payload.calls.length);

        // 7. Decode BridgeData and SwapData from calldata using the library
        for (uint256 i = 0; i < payload.calls.length; i++) {
            (ILiFi.BridgeData memory bridgeData, LibSwap.SwapData[] memory swapData) =
                AnypayLiFiDecoder.decodeLiFiDataOrRevert(payload.calls[i].data);

            inferredLifiInfos[i] = AnypayLiFiInterpreter.getOriginSwapInfo(bridgeData, swapData);
        }

        // 8. Validate the attestations
        AnypayLiFiInterpreter.validateLifiInfos(inferredLifiInfos, attestationLifiInfos);

        // 9. Hash the lifi intent params
        bytes32 lifiIntentHash = AnypayIntentParams.getAnypayLifiInfoHash(attestationLifiInfos, attestationSigner);

        // 10. Return the lifi intent hashed params
        return lifiIntentHash;
    }

    // -------------------------------------------------------------------------
    // Internal Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Decodes a combined signature into LiFi information and the attestation signature.
     * @dev Assumes _signature is abi.encode(AnypayLifiInfo[] memory, bytes memory).
     * @param _signature The combined signature bytes.
     * @return _lifiInfos Array of AnypayLifiInfo structs.
     * @return _attestationSignature The ECDSA signature for attestation.
     */
    function _decodeSignature(bytes calldata _signature)
        internal
        pure
        returns (AnypayLifiInfo[] memory _lifiInfos, bytes memory _attestationSignature)
    {
        // Assuming _signature is abi.encode(AnypayLifiInfo[] memory, bytes memory)
        (_lifiInfos, _attestationSignature) = abi.decode(_signature, (AnypayLifiInfo[], bytes));
    }
}
