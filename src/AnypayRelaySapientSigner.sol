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
    // Function Selectors
    // -------------------------------------------------------------------------

    bytes4 private constant _START_BRIDGE_TOKENS_VIA_RELAY = bytes4(
        keccak256(
            "startBridgeTokensViaRelay((bytes32,string,string,address,address,address,uint256,uint256,bool,bool),(bytes32,bytes32,bytes32,bytes))"
        )
    );
    bytes4 private constant _SWAP_AND_START_BRIDGE_TOKENS_VIA_RELAY = bytes4(
        keccak256(
            "swapAndStartBridgeTokensViaRelay((bytes32,string,string,address,address,address,uint256,uint256,bool,bool),(address,address,address,address,uint256,bytes,bool)[],(bytes32,bytes32,bytes32,bytes))"
        )
    );

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
        // 1. Validate outer Payload
        if (payload.kind != Payload.KIND_TRANSACTIONS) {
            revert InvalidPayloadKind();
        }

        if (payload.calls.length == 0) {
            revert InvalidCallsLength();
        }

        // 2. Decode the signature
        (
            AnypayRelayInfo[] memory attestedRelayInfos,
            bytes memory attestationSignature,
            address attestationSigner
        ) = decodeSignature(encodedSignature);

        // 3. Recover the signer from the attestation signature
        address recoveredAttestationSigner =
            keccak256(abi.encode(payload.hashFor(address(0)))).recover(attestationSignature);

        if (recoveredAttestationSigner != attestationSigner) {
            revert InvalidAttestationSigner(attestationSigner, recoveredAttestationSigner);
        }

        // 4. Decode and validate calls
        AnypayRelayInfo[] memory inferredRelayInfos = new AnypayRelayInfo[](payload.calls.length);

        for (uint256 i = 0; i < payload.calls.length; i++) {
            inferredRelayInfos[i] = _decodeRelayCalldata(payload.calls[i].data, payload.calls[i].to);
        }

        // 5. Validate attestations
        if (!_validateRelayInfos(inferredRelayInfos, attestedRelayInfos)) {
            revert InvalidAttestation();
        }

        // 6. Hash the relay intent params
        bytes32 relayIntentHash = keccak256(abi.encode(attestedRelayInfos, attestationSigner));

        return relayIntentHash;
    }

    // -------------------------------------------------------------------------
    // Internal Functions
    // -------------------------------------------------------------------------

    function _decodeRelayCalldata(bytes calldata callData, address target) internal pure returns (AnypayRelayInfo memory) {
        bytes4 selector = bytes4(callData[:4]);
        ILiFi.BridgeData memory bridgeData;
        RelayData memory relayData;

        if (selector == _START_BRIDGE_TOKENS_VIA_RELAY) {
            (bridgeData, relayData) = abi.decode(callData[4:], (ILiFi.BridgeData, RelayData));
        } else if (selector == _SWAP_AND_START_BRIDGE_TOKENS_VIA_RELAY) {
            (bridgeData, , relayData) = abi.decode(callData[4:], (ILiFi.BridgeData, LibSwap.SwapData[], RelayData));
        } else {
            revert InvalidCalldata();
        }

        return AnypayRelayInfo({
            requestId: relayData.requestId,
            signature: relayData.signature,
            nonEVMReceiver: relayData.nonEVMReceiver,
            receivingAssetId: relayData.receivingAssetId,
            sendingAssetId: bridgeData.sendingAssetId,
            receiver: bridgeData.receiver,
            destinationChainId: bridgeData.destinationChainId,
            minAmount: bridgeData.minAmount,
            target: target
        });
    }

    function _validateRelayInfos(
        AnypayRelayInfo[] memory inferredRelayInfos,
        AnypayRelayInfo[] memory attestedRelayInfos
    ) internal view returns (bool) {
        if (inferredRelayInfos.length != attestedRelayInfos.length) {
            revert MismatchedRelayInfoLengths();
        }

        uint256 numInfos = attestedRelayInfos.length;
        if (numInfos == 0) {
            return true;
        }

        bool[] memory inferredInfoUsed = new bool[](numInfos);

        for (uint256 i = 0; i < numInfos; i++) {
            AnypayRelayInfo memory attestedInfo = attestedRelayInfos[i];
            bool foundMatch = false;

            for (uint256 j = 0; j < numInfos; j++) {
                if (inferredInfoUsed[j]) {
                    continue;
                }

                AnypayRelayInfo memory inferredInfo = inferredRelayInfos[j];

                // Main matching logic
                if (
                    attestedInfo.requestId == inferredInfo.requestId &&
                    attestedInfo.target == inferredInfo.target &&
                    attestedInfo.sendingAssetId == inferredInfo.sendingAssetId &&
                    attestedInfo.destinationChainId == inferredInfo.destinationChainId &&
                    attestedInfo.receiver == inferredInfo.receiver &&
                    attestedInfo.nonEVMReceiver == inferredInfo.nonEVMReceiver &&
                    attestedInfo.receivingAssetId == inferredInfo.receivingAssetId
                ) {
                    // Check amount
                    if (inferredInfo.minAmount > attestedInfo.minAmount) {
                        revert InferredAmountTooHigh(inferredInfo.minAmount, attestedInfo.minAmount);
                    }

                    // Check relay solver signature
                    bytes32 message = keccak256(
                        abi.encodePacked(
                            inferredInfo.requestId,
                            block.chainid,
                            bytes32(uint256(uint160(inferredInfo.target))),
                            bytes32(uint256(uint160(inferredInfo.sendingAssetId))),
                            _getMappedChainId(inferredInfo.destinationChainId),
                            inferredInfo.receiver == NON_EVM_ADDRESS
                                ? inferredInfo.nonEVMReceiver
                                : bytes32(uint256(uint160(inferredInfo.receiver))),
                            inferredInfo.receivingAssetId
                        )
                    );

                    address signer = message.recover(inferredInfo.signature);
                    if (signer != RELAY_SOLVER) {
                        revert InvalidRelayQuote();
                    }

                    inferredInfoUsed[j] = true;
                    foundMatch = true;
                    break;
                }
            }

            if (!foundMatch) {
                revert NoMatchingInferredInfoFound(attestedInfo.requestId);
            }
        }

        return true;
    }

    /**
     * @notice Decodes a combined signature into Relay information and the attestation signature.
     * @dev Assumes _signature is abi.encode(AnypayRelayInfo[] memory, bytes memory, address).
     * @param _signature The combined signature bytes.
     * @return _relayInfos Array of AnypayRelayInfo structs.
     * @return _attestationSignature The ECDSA signature for attestation.
     * @return _attestationSigner The address of the signer of the attestation.
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

    /**
     * @notice get Relay specific chain id for non-EVM chains
     *         IDs found here  https://li.quest/v1/chains?chainTypes=UTXO,SVM
     * @param chainId LIFI specific chain id
     */
    function _getMappedChainId(
        uint256 chainId
    ) public pure returns (uint256) {
        // Bitcoin
        if (chainId == 20000000000001) {
            return 8253038;
        }

        // Solana
        if (chainId == 1151111081099710) {
            return 792703809;
        }

        return chainId;
    }
} 
