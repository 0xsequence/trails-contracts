// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {LifiSessionValidatorModule} from "../../../src/modules/LifiSessionValidatorModule.sol";
import {Attestation, LibAttestation, AuthData} from "wallet-contracts-v3/extensions/sessions/implicit/Attestation.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

// --- Mock Contracts ---

contract MockLifiDiamond {
    event CallReceived(address caller, uint256 value, bytes data);

    bool public shouldRevert = false;
    bytes public revertData;

    error MockLifiDiamondGenericRevert();

    fallback() external payable {
        emit CallReceived(msg.sender, msg.value, msg.data);
        if (shouldRevert) {
            bytes memory localRevertData = revertData;
            if (localRevertData.length > 0) {
                assembly {
                    revert(add(localRevertData, 0x20), mload(localRevertData))
                }
            } else {
                revert MockLifiDiamondGenericRevert();
            }
        }
    }

    receive() external payable {}

    function setRevert(bool _shouldRevert, bytes memory _revertData) external {
        shouldRevert = _shouldRevert;
        revertData = _revertData;
    }

    // Example mock LiFi function
    function mockSwap(uint256 amountIn, address tokenIn, uint256 amountOutMin, address tokenOut) external payable {
        // Mock logic
    }
}

// --- Test Contract ---

contract LifiSessionValidatorModuleTest is Test {
    using LibAttestation for Attestation;

    LifiSessionValidatorModule internal module;
    MockLifiDiamond internal mockLifi;

    // Users
    address internal walletOwner; // Signs attestations (becomes approvedSigner in attestation)
    uint256 internal walletOwnerPk;
    address internal relayer; // Calls executeWithLifiSession
    address internal otherUser;

    // Default values for attestation
    uint256 internal defaultNonce;
    uint256 internal defaultExpiry;
    bytes32 internal defaultConstraintsHash;

    function setUp() public {
        // Create users
        walletOwnerPk = 0x1234; // Example private key
        walletOwner = vm.addr(walletOwnerPk);
        relayer = vm.addr(0x5678);
        otherUser = vm.addr(0x9abc);

        // Deploy Mocks and Module
        mockLifi = new MockLifiDiamond();
        module = new LifiSessionValidatorModule(address(mockLifi));

        // Initialize default attestation values
        defaultNonce = 0;
        defaultExpiry = block.timestamp + 1 days;
        defaultConstraintsHash = bytes32(0); // No constraints by default

        // Give walletOwner some ETH to sign messages if needed (though signing is off-chain)
        vm.deal(walletOwner, 10 ether);
        // Give relayer some ETH to make calls
        vm.deal(relayer, 10 ether);
    }

    // --- Helper Functions ---

    function _createAttestation(
        address _approvedSigner, // Who is authorized by this attestation (signs it)
        address _targetContract, // Intended target for the LiFi call
        uint256 _value,
        bytes memory _callData,
        uint256 _nonce,
        uint256 _expiry,
        bytes32 _constraintsHash // Hash of any specific constraints
    ) internal view returns (Attestation memory attestation) {
        // Construct LifiApplicationData
        LifiSessionValidatorModule.LifiApplicationData memory appData = LifiSessionValidatorModule.LifiApplicationData({
            targetContract: _targetContract,
            value: _value,
            nonce: _nonce,
            expiry: _expiry,
            callDataHash: keccak256(_callData),
            constraintsHash: _constraintsHash
        });

        bytes memory packedAppData = abi.encode(appData);

        // The module's address (address(module)) is the audience context
        // The _approvedSigner's context (wallet address if Sequence Wallet, or _approvedSigner if EOA directly) is issuer context
        // For simplicity in module testing, using _approvedSigner as issuer context for now.
        // In a real Sequence wallet, `walletAddress` would be the Sequence wallet's address.
        // Here, `module` is the wallet context for issuerHash because it's `address(this)` inside module
        address walletContextForIssuer = address(module);

        attestation = Attestation({
            approvedSigner: _approvedSigner,
            identityType: module.LIFI_ATTESTATION_IDENTITY_TYPE(),
            issuerHash: keccak256(abi.encodePacked(walletContextForIssuer, module.LIFI_SESSION_ISSUER_SUFFIX())),
            audienceHash: keccak256(abi.encodePacked(address(module), module.LIFI_SESSION_AUDIENCE_SUFFIX())),
            applicationData: packedAppData,
            authData: AuthData({redirectUrl: ""})
        });
    }

    function _signAttestation(Attestation memory _attestation, uint256 _signerPrivateKey)
        internal
        pure
        returns (bytes memory signature)
    {
        bytes32 attestationHash = _attestation.toHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_signerPrivateKey, attestationHash);
        signature = abi.encodePacked(r, s, v);
    }

    // --- Test Cases ---

    function test_Execute_Success() public {
        uint256 callValue = 1 ether;
        bytes memory callData =
            abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector, 100, address(1), 90, address(2));

        Attestation memory att = _createAttestation(
            walletOwner, // Signer is walletOwner
            address(mockLifi),
            callValue,
            callData,
            defaultNonce,
            defaultExpiry,
            defaultConstraintsHash
        );
        bytes memory signature = _signAttestation(att, walletOwnerPk);

        Payload.Call memory lifiCall = Payload.Call({
            to: address(mockLifi),
            value: callValue,
            data: callData,
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
        });

        vm.prank(relayer);
        vm.deal(address(module), callValue); // Ensure module has ETH to forward if needed

        // Expect event
        vm.expectEmit(true, true, true, true, address(module));
        emit LifiSessionValidatorModule.LifiSessionExecuted(
            address(module), // Wallet address (module itself)
            walletOwner, // Approved Signer
            defaultNonce,
            address(mockLifi),
            callValue,
            callData
        );

        module.executeWithLifiSession{value: callValue}(att, signature, lifiCall);

        assertEq(module.nonces(walletOwner), defaultNonce + 1, "Nonce should increment");
        // Further checks on MockLifiDiamond if needed (e.g., emitted events from mock)
    }

    // --- Revert Scenarios ---

    function test_Revert_InvalidSignature_WrongKey() public {
        bytes memory callData = abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector);
        Payload.Call memory lifiCall =
            Payload.Call(address(mockLifi), 0, callData, 0, false, false, Payload.BEHAVIOR_REVERT_ON_ERROR);

        Attestation memory att =
            _createAttestation(walletOwner, address(mockLifi), 0, callData, 0, defaultExpiry, defaultConstraintsHash);
        uint256 otherUserPk = 0x9999; // Different private key
        bytes memory signature = _signAttestation(att, otherUserPk);

        vm.prank(relayer);
        vm.expectRevert(LifiSessionValidatorModule.InvalidLifiAttestationSignature.selector);
        module.executeWithLifiSession(att, signature, lifiCall);
    }

    function test_Revert_InvalidSignature_Malformed() public {
        bytes memory callData = abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector);
        Payload.Call memory lifiCall =
            Payload.Call(address(mockLifi), 0, callData, 0, false, false, Payload.BEHAVIOR_REVERT_ON_ERROR);
        Attestation memory att =
            _createAttestation(walletOwner, address(mockLifi), 0, callData, 0, defaultExpiry, defaultConstraintsHash);
        bytes memory badSignature = hex"1234";

        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, bytes(badSignature).length));
        module.executeWithLifiSession(att, badSignature, lifiCall);
    }

    function test_Revert_MismatchedSigner() public {
        bytes memory callData = abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector);
        Payload.Call memory lifiCall =
            Payload.Call(address(mockLifi), 0, callData, 0, false, false, Payload.BEHAVIOR_REVERT_ON_ERROR);

        Attestation memory att =
            _createAttestation(otherUser, address(mockLifi), 0, callData, 0, defaultExpiry, defaultConstraintsHash); // Attestation for otherUser
        bytes memory signature = _signAttestation(att, walletOwnerPk); // But signed by walletOwner

        vm.prank(relayer);
        vm.expectRevert(LifiSessionValidatorModule.InvalidLifiAttestationSignature.selector);
        module.executeWithLifiSession(att, signature, lifiCall);
    }

    function test_Revert_InvalidIdentityType() public {
        bytes memory callData = abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector);
        Payload.Call memory lifiCall =
            Payload.Call(address(mockLifi), 0, callData, 0, false, false, Payload.BEHAVIOR_REVERT_ON_ERROR);
        Attestation memory att =
            _createAttestation(walletOwner, address(mockLifi), 0, callData, 0, defaultExpiry, defaultConstraintsHash);
        att.identityType = bytes4(keccak256("WRONG_TYPE"));
        bytes memory signature = _signAttestation(att, walletOwnerPk);

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                LifiSessionValidatorModule.InvalidLifiAttestationIdentity.selector,
                att.identityType,
                module.LIFI_ATTESTATION_IDENTITY_TYPE()
            )
        );
        module.executeWithLifiSession(att, signature, lifiCall);
    }

    function test_Revert_InvalidAudience() public {
        bytes memory callData = abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector);
        Payload.Call memory lifiCall =
            Payload.Call(address(mockLifi), 0, callData, 0, false, false, Payload.BEHAVIOR_REVERT_ON_ERROR);
        Attestation memory att =
            _createAttestation(walletOwner, address(mockLifi), 0, callData, 0, defaultExpiry, defaultConstraintsHash);
        bytes32 originalAudience = att.audienceHash;
        att.audienceHash = keccak256(abi.encodePacked(otherUser, module.LIFI_SESSION_AUDIENCE_SUFFIX())); // Wrong audience
        bytes memory signature = _signAttestation(att, walletOwnerPk);

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                LifiSessionValidatorModule.InvalidLifiAttestationAudience.selector, att.audienceHash, originalAudience
            )
        );
        module.executeWithLifiSession(att, signature, lifiCall);
    }

    function test_Revert_InvalidIssuer() public {
        bytes memory callData = abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector);
        Payload.Call memory lifiCall =
            Payload.Call(address(mockLifi), 0, callData, 0, false, false, Payload.BEHAVIOR_REVERT_ON_ERROR);
        Attestation memory att =
            _createAttestation(walletOwner, address(mockLifi), 0, callData, 0, defaultExpiry, defaultConstraintsHash);
        bytes32 originalIssuer = att.issuerHash;
        att.issuerHash = keccak256(abi.encodePacked(otherUser, module.LIFI_SESSION_ISSUER_SUFFIX())); // Wrong issuer context
        bytes memory signature = _signAttestation(att, walletOwnerPk);

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                LifiSessionValidatorModule.InvalidLifiAttestationIssuer.selector, att.issuerHash, originalIssuer
            )
        );
        module.executeWithLifiSession(att, signature, lifiCall);
    }

    function test_Revert_InvalidTarget_Attestation() public {
        bytes memory callData = abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector);
        Payload.Call memory lifiCall =
            Payload.Call(address(mockLifi), 0, callData, 0, false, false, Payload.BEHAVIOR_REVERT_ON_ERROR);

        // Attestation's appData points to a wrong target
        Attestation memory att =
            _createAttestation(walletOwner, otherUser, 0, callData, 0, defaultExpiry, defaultConstraintsHash);
        bytes memory signature = _signAttestation(att, walletOwnerPk);

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                LifiSessionValidatorModule.InvalidTargetAddress.selector, address(mockLifi), otherUser
            )
        );
        module.executeWithLifiSession(att, signature, lifiCall);
    }

    function test_Revert_InvalidTarget_LifiCall() public {
        bytes memory callData = abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector);
        // Actual call is to a wrong target
        Payload.Call memory lifiCall =
            Payload.Call(otherUser, 0, callData, 0, false, false, Payload.BEHAVIOR_REVERT_ON_ERROR);

        // Attestation's appData points to the correct mockLifi
        Attestation memory att =
            _createAttestation(walletOwner, address(mockLifi), 0, callData, 0, defaultExpiry, defaultConstraintsHash);
        bytes memory signature = _signAttestation(att, walletOwnerPk);

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                LifiSessionValidatorModule.InvalidTargetAddress.selector, address(mockLifi), otherUser
            )
        );
        module.executeWithLifiSession(att, signature, lifiCall);
    }

    function test_Revert_MismatchedValue() public {
        bytes memory callData = abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector);
        Payload.Call memory lifiCall =
            Payload.Call(address(mockLifi), 1 ether, callData, 0, false, false, Payload.BEHAVIOR_REVERT_ON_ERROR); // Call has 1 ether

        // Attestation's appData indicates 0 value
        Attestation memory att =
            _createAttestation(walletOwner, address(mockLifi), 0, callData, 0, defaultExpiry, defaultConstraintsHash);
        bytes memory signature = _signAttestation(att, walletOwnerPk);

        vm.prank(relayer);
        vm.expectRevert(LifiSessionValidatorModule.LifiAttestationMismatch.selector);
        module.executeWithLifiSession{value: 1 ether}(att, signature, lifiCall);
    }

    function test_Revert_MismatchedCallData() public {
        bytes memory callDataActual =
            abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector, 1, address(0), 1, address(0));
        bytes memory callDataAttested =
            abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector, 2, address(0), 2, address(0)); // Different calldata

        Payload.Call memory lifiCall =
            Payload.Call(address(mockLifi), 0, callDataActual, 0, false, false, Payload.BEHAVIOR_REVERT_ON_ERROR);

        // Attestation's appData has hash of callDataAttested
        Attestation memory att = _createAttestation(
            walletOwner, address(mockLifi), 0, callDataAttested, 0, defaultExpiry, defaultConstraintsHash
        );
        bytes memory signature = _signAttestation(att, walletOwnerPk);

        vm.prank(relayer);
        vm.expectRevert(LifiSessionValidatorModule.LifiAttestationMismatch.selector);
        module.executeWithLifiSession(att, signature, lifiCall);
    }

    function test_Revert_Expired() public {
        bytes memory callData = abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector);
        Payload.Call memory lifiCall =
            Payload.Call(address(mockLifi), 0, callData, 0, false, false, Payload.BEHAVIOR_REVERT_ON_ERROR);
        uint256 pastExpiry = block.timestamp - 1 seconds;

        Attestation memory att =
            _createAttestation(walletOwner, address(mockLifi), 0, callData, 0, pastExpiry, defaultConstraintsHash);
        bytes memory signature = _signAttestation(att, walletOwnerPk);

        vm.prank(relayer);
        uint256 expectedTimestampAtCall = block.timestamp + 10;
        vm.warp(expectedTimestampAtCall);

        vm.expectRevert(
            abi.encodeWithSelector(
                LifiSessionValidatorModule.LifiAttestationExpired.selector, pastExpiry, expectedTimestampAtCall
            )
        );
        module.executeWithLifiSession(att, signature, lifiCall);
    }

    function test_Revert_Nonce_Incorrect() public {
        bytes memory callData = abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector);
        Payload.Call memory lifiCall =
            Payload.Call(address(mockLifi), 0, callData, 0, false, false, Payload.BEHAVIOR_REVERT_ON_ERROR);
        uint256 wrongNonce = 1; // Expected is 0

        Attestation memory att = _createAttestation(
            walletOwner, address(mockLifi), 0, callData, wrongNonce, defaultExpiry, defaultConstraintsHash
        );
        bytes memory signature = _signAttestation(att, walletOwnerPk);

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(LifiSessionValidatorModule.LifiAttestationNonceInvalid.selector, 0, wrongNonce)
        );
        module.executeWithLifiSession(att, signature, lifiCall);
    }

    // function test_Revert_Nonce_Replay() public {
    //     bytes memory callData = abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector);
    //     Payload.Call memory lifiCall = Payload.Call(address(mockLifi), 0, callData, 0, false, false, Payload.BEHAVIOR_REVERT_ON_ERROR);

    //     // First call (Nonce 0)
    //     Attestation memory att0 = _createAttestation(walletOwner, address(mockLifi), 0, callData, 0, defaultExpiry, defaultConstraintsHash);
    //     bytes memory sig0 = _signAttestation(att0, walletOwnerPk);
    //     vm.prank(relayer);
    //     module.executeWithLifiSession(att0, sig0, lifiCall);
    //     assertEq(module.nonces(walletOwner), 1, "Nonce should be 1 after first call");

    //     // --- Start Diagnostic ---
    //     LifiSessionValidatorModule.LifiApplicationData memory decodedAppDataFromAtt0 = 
    //         abi.decode(att0.applicationData, (LifiSessionValidatorModule.LifiApplicationData));
    //     console.log("Original test_Revert_Nonce_Replay - Nonce in att0 for replay:", decodedAppDataFromAtt0.nonce); // Should be 0
    //     console.log("Original test_Revert_Nonce_Replay - Expected nonce from module state for replay:", module.nonces(walletOwner)); // Should be 1
    //     // --- End Diagnostic ---

    //     // Second call (Attempt to reuse Nonce 0)
    //     vm.prank(relayer);
    //     vm.expectRevert(abi.encodeWithSelector(LifiSessionValidatorModule.LifiAttestationNonceInvalid.selector, 1, 0)); 
    //     module.executeWithLifiSession(att0, sig0, lifiCall); // Reusing att0 and sig0
    // }

    function test_Revert_LifiCallFailed() public {
        bytes memory callData = abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector);
        Payload.Call memory lifiCall =
            Payload.Call(address(mockLifi), 0, callData, 0, false, false, Payload.BEHAVIOR_REVERT_ON_ERROR);

        Attestation memory att =
            _createAttestation(walletOwner, address(mockLifi), 0, callData, 0, defaultExpiry, defaultConstraintsHash);
        bytes memory signature = _signAttestation(att, walletOwnerPk);

        // Configure mock to revert
        bytes memory mockRevertData = abi.encodeWithSignature("Error(string)", "LiFi call deliberately failed");
        mockLifi.setRevert(true, mockRevertData);

        vm.prank(relayer);
        vm.expectRevert(LifiSessionValidatorModule.LifiCallFailed.selector); // Expect module's own error
        module.executeWithLifiSession(att, signature, lifiCall);
    }

    function test_Revert_LifiCallFailed_NoReason() public {
        bytes memory callData = abi.encodeWithSelector(MockLifiDiamond.mockSwap.selector);
        Payload.Call memory lifiCall =
            Payload.Call(address(mockLifi), 0, callData, 0, false, false, Payload.BEHAVIOR_REVERT_ON_ERROR);

        Attestation memory att =
            _createAttestation(walletOwner, address(mockLifi), 0, callData, 0, defaultExpiry, defaultConstraintsHash);
        bytes memory signature = _signAttestation(att, walletOwnerPk);

        mockLifi.setRevert(true, ""); // Revert with no specific data

        vm.prank(relayer);
        // This will revert with no data or a generic error message if the assembly block can't get revert data.
        // For a simple revert in the mock without data, Solidity usually bubbles it up as such.
        // Exact revert data check might be tricky if it's an empty revert.
        vm.expectRevert(LifiSessionValidatorModule.LifiCallFailed.selector); // Module reverts with its own error now
        module.executeWithLifiSession(att, signature, lifiCall);
    }

    // TODO: Constraint Validation Tests (If implemented)
    // function test_Execute_WithValidConstraints() public {}
    // function test_Revert_InvalidConstraints() public {}
}
