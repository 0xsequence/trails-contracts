// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Attestation, LibAttestation} from "wallet-contracts-v3/extensions/sessions/implicit/Attestation.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
// import {ILiFi} from "lifi-contracts/interfaces/ILiFi.sol"; // Removed unused import
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol"; // For LibSwap.SwapData type
import {AnypayLiFiDecoder} from "../libraries/AnypayLiFiDecoder.sol";
// import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol"; // Keep for reference if contract signer needed

/**
 * @title LifiSessionValidatorModule
 * @notice A Sequence v3 wallet module to validate and execute LiFi actions based on off-chain attestations,
 *         targeting a specific LiFi Diamond contract.
 * This allows relayers to perform LiFi swaps/bridges authorized by a user's signature
 * on an attestation, without requiring per-transaction configuration updates or pre-signed transactions.
 */
contract LifiSessionValidatorModule {
    using LibAttestation for Attestation;

    // -------------------------------------------------------------------------
    // Immutables
    // -------------------------------------------------------------------------

    address public immutable TARGET_LIFI_DIAMOND;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    bytes4 public constant LIFI_ATTESTATION_IDENTITY_TYPE = bytes4(keccak256("LifiSessionAttestation_v1"));
    string public constant LIFI_SESSION_AUDIENCE_SUFFIX = "LifiSessionAudience_v1";
    string public constant LIFI_SESSION_ISSUER_SUFFIX = "LifiSessionIssuer_v1";

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event LifiSessionExecuted(
        address indexed wallet,
        address indexed approvedSigner,
        uint256 nonce,
        address targetContract,
        uint256 value,
        bytes callData
    );

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error InvalidLifiAttestationSignature();
    error LifiAttestationExpired(uint256 expiry, uint256 blockTimestamp);
    error LifiAttestationNonceInvalid(uint256 expectedNonce, uint256 actualNonce);
    error LifiAttestationMismatch(); // If attestation details don't match Payload.Call
    error InvalidLifiAttestationSigner(address expectedSigner, address actualSigner);
    error InvalidLifiAttestationAudience(bytes32 expectedAudienceHash, bytes32 actualAudienceHash);
    error InvalidLifiAttestationIssuer(bytes32 expectedIssuerHash, bytes32 actualIssuerHash);
    error InvalidLifiAttestationIdentity(bytes4 expectedIdentity, bytes4 actualIdentity);
    error InvalidTargetAddress(address expectedTarget, address actualTarget);
    error InvalidLifiDiamondAddress();
    error LifiCallFailed();

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    /**
     * @notice Packed structure for applicationData within the Attestation.
     * @dev abi.encodePacked(address targetContract, uint256 value, uint256 nonce, uint256 expiry, bytes32 callDataHash, bytes32 constraintsHash)
     */
    struct LifiApplicationData {
        address targetContract;
        uint256 value;
        uint256 nonce;
        uint256 expiry;
        bytes32 callDataHash;
        bytes32 constraintsHash; // keccak256 of packed constraints, or bytes32(0) if none
    }

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    /**
     * @notice Tracks the next valid nonce for a given wallet and session signer.
     * @dev mapping: walletAddress => sessionSigner => nonce
     * @dev The walletAddress is implicitly address(this) due to delegatecall module execution.
     */
    mapping(address => uint256) public nonces; // signer => nonce

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _lifiDiamondAddress) {
        if (_lifiDiamondAddress == address(0)) {
            revert InvalidLifiDiamondAddress();
        }
        TARGET_LIFI_DIAMOND = _lifiDiamondAddress;
    }

    /**
     * @dev External view helper to call the library's decodeSwapDataTuple.
     *      This allows using try/catch with the decoding logic from a contract context.
     *      Accepts `bytes calldata` as that's what `_lifiCall.data` is.
     */
    function _getDecodedSwapDataForTryCatchSession(bytes calldata data) external view returns (LibSwap.SwapData[] memory) {
        // Library function expects `bytes memory`, calldata will be copied automatically.
        return AnypayLiFiDecoder.decodeSwapDataTuple(data);
    }

    // -------------------------------------------------------------------------
    // Logic
    // -------------------------------------------------------------------------

    /**
     * @notice Executes a LiFi call authorized by a signed attestation.
     * @param _attestation The signed attestation data.
     * @param _signature The signature over the attestation hash.
     * @param _lifiCall The specific LiFi call payload (to, value, data) to execute.
     *                  This MUST match the details encoded within _attestation.applicationData.
     */
    function executeWithLifiSession(
        Attestation calldata _attestation,
        bytes calldata _signature,
        Payload.Call calldata _lifiCall
    ) external payable {
        // Mark payable to allow receiving ETH if needed for the module's execution flow
        address walletAddress = address(this); // Wallet address in module context
        address approvedSigner = _attestation.approvedSigner;

        // 1. Verify Signature and Signer
        bytes32 attestationHash = _attestation.toHash();
        address recoveredSigner = ECDSA.recover(attestationHash, _signature); 

        if (recoveredSigner == address(0) || recoveredSigner != approvedSigner) {
            revert InvalidLifiAttestationSignature();
        }

        // 2. Verify Attestation Identity, Audience, and Issuer
        if (_attestation.identityType != LIFI_ATTESTATION_IDENTITY_TYPE) {
            revert InvalidLifiAttestationIdentity(_attestation.identityType, LIFI_ATTESTATION_IDENTITY_TYPE);
        }

        bytes32 expectedAudienceHash = keccak256(abi.encodePacked(address(this), LIFI_SESSION_AUDIENCE_SUFFIX));
        if (_attestation.audienceHash != expectedAudienceHash) {
            revert InvalidLifiAttestationAudience(_attestation.audienceHash, expectedAudienceHash);
        }

        bytes32 expectedIssuerHash = keccak256(abi.encodePacked(walletAddress, LIFI_SESSION_ISSUER_SUFFIX));
        if (_attestation.issuerHash != expectedIssuerHash) {
            revert InvalidLifiAttestationIssuer(_attestation.issuerHash, expectedIssuerHash);
        }

        // 3. Decode applicationData
        LifiApplicationData memory appData = abi.decode(_attestation.applicationData, (LifiApplicationData));

        // 4. Verify target address and applicationData matches _lifiCall
        if (appData.targetContract != TARGET_LIFI_DIAMOND) {
            revert InvalidTargetAddress(TARGET_LIFI_DIAMOND, appData.targetContract);
        }
        if (_lifiCall.to != TARGET_LIFI_DIAMOND) {
            revert InvalidTargetAddress(TARGET_LIFI_DIAMOND, _lifiCall.to);
        }

        if (appData.value != _lifiCall.value || appData.callDataHash != keccak256(_lifiCall.data)) {
            revert LifiAttestationMismatch();
        }

        // 5. Validate Expiry
        if (block.timestamp > appData.expiry) {
            revert LifiAttestationExpired(appData.expiry, block.timestamp);
        }

        // 6. Validate and Consume Nonce
        uint256 expectedNonce = nonces[approvedSigner];
        if (appData.nonce != expectedNonce) {
            revert LifiAttestationNonceInvalid(expectedNonce, appData.nonce);
        }
        nonces[approvedSigner]++; // Consume nonce

        // 7. Optional: Validate Constraints
        // Example: bytes32 actualConstraintsHash = keccak256(abi.encodePacked(...));
        // if (appData.constraintsHash != actualConstraintsHash && appData.constraintsHash != bytes32(0)) {
        //     revert LifiConstraintMismatch(); // Define this error
        // }

        // 8. Decode BridgeData and SwapData from calldata using the library
        AnypayLiFiDecoder.emitDecodedBridgeData(_lifiCall.data);
        
        LibSwap.SwapData[] memory _decodedSwapDataArray;
        try this._getDecodedSwapDataForTryCatchSession(_lifiCall.data) returns (LibSwap.SwapData[] memory _sds) {
            _decodedSwapDataArray = _sds;
        } catch Error(string memory /*reason*/) {
            _decodedSwapDataArray = new LibSwap.SwapData[](0);
        } catch Panic(uint256 /*errorCode*/) {
            _decodedSwapDataArray = new LibSwap.SwapData[](0);
        }

        if (_decodedSwapDataArray.length > 0) {
            emit AnypayLiFiDecoder.DecodedSwapData(
                _decodedSwapDataArray[0].callTo,
                _decodedSwapDataArray[0].sendingAssetId,
                _decodedSwapDataArray[0].receivingAssetId,
                _decodedSwapDataArray[0].fromAmount,
                _decodedSwapDataArray.length
            );
        } else {
            emit AnypayLiFiDecoder.DecodedSwapData(address(0), address(0), address(0), 0, 0);
        }

        // 9. Execute LiFi Call
        (bool success,) = _lifiCall.to.call{value: _lifiCall.value}(_lifiCall.data);

        if (!success) {
            revert LifiCallFailed(); 
        }

        emit LifiSessionExecuted(
            walletAddress, approvedSigner, appData.nonce, _lifiCall.to, _lifiCall.value, _lifiCall.data
        );
    }
}
