// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {AnypayLiFiDecoder} from "./libraries/AnypayLiFiDecoder.sol";
import {AnypayLifiInterpreter, AnypayLifiInfo} from "./libraries/AnypayLifiInterpreter.sol";
import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";

/**
 * @title AnypayLifiSapientSigner
 * @notice An SapientSigner module for Sequence v3 wallets, designed to facilitate LiFi actions
 *         through the sapient signer module. It validates off-chain attestations to authorize
 *         operations on a specific LiFi Diamond contract. This enables relayers to execute LiFi
 *         swaps/bridges as per user-attested parameters, without direct wallet pre-approval for each transaction.
 */
contract AnypayLifiSapientSigner is ISapient {
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
    error InvalidLifiDiamondAddress();
    error InvalidPayloadKind();
    error InvalidCallsLength();

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

        // 4. Recover the signer from the signature
        address attestationSigner = ECDSA.recover(payload.hashFor(address(0)), encodedSignature);

        // 5. Initialize structs to store decoded data
        AnypayLifiInfo[] memory lifiInfos = new AnypayLifiInfo[](payload.calls.length);

        // 6. Decode BridgeData and SwapData from calldata using the library
        for (uint256 i = 0; i < payload.calls.length; i++) {
            (ILiFi.BridgeData memory bridgeData, LibSwap.SwapData[] memory swapData) =
                AnypayLiFiDecoder.tryDecodeBridgeAndSwapData(payload.calls[i].data);
            lifiInfos[i] = AnypayLifiInterpreter.getOriginSwapInfo(bridgeData, swapData);
        }

        // 7. Hash the lifi intent params
        bytes32 lifiIntentHash = AnypayLifiInterpreter.getAnypayLifiInfoHash(lifiInfos, attestationSigner);

        // 8. Return the lifi intent hashed params
        return lifiIntentHash;
    }
}
