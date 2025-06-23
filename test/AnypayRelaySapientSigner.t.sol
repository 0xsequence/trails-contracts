// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {AnypayRelaySapientSigner} from "@/AnypayRelaySapientSigner.sol";
import {AnypayExecutionInfo} from "@/interfaces/AnypayExecutionInfo.sol";
import {AnypayExecutionInfoParams} from "@/libraries/AnypayExecutionInfoParams.sol";

// Mock ERC20 contract for testing transfers
contract MockERC20 is Test {
    function transfer(address, /*to*/ uint256 /*amount*/ ) external pure returns (bool) {
        return true;
    }
}

contract AnypayRelaySapientSignerTest is Test {
    using Payload for Payload.Decoded;

    AnypayRelaySapientSigner public signerContract;
    address public relaySolverAddress;
    address public userWalletAddress;
    uint256 public userSignerPrivateKey;
    address public userSignerAddress;

    MockERC20 public mockToken;

    function setUp() public {
        relaySolverAddress = makeAddr("relaySolver");
        // The AnypayRelaySapientSigner is configured with the address of the relay solver.
        signerContract = new AnypayRelaySapientSigner(relaySolverAddress);

        userSignerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        userSignerAddress = vm.addr(userSignerPrivateKey);
        userWalletAddress = makeAddr("userWallet");

        mockToken = new MockERC20();
    }

    function test_RecoverSingleRelayCall_ERC20_ValidSignature() public {
        // 1. Prepare the call data for the relay
        address receiver = relaySolverAddress;
        uint256 amount = 1 ether;
        bytes32 requestId = keccak256("erc20_test_request");

        // This would be the data for an ERC20 transfer call in a real scenario
        bytes memory callDataToToken = abi.encodeWithSelector(MockERC20.transfer.selector, receiver, amount);
        callDataToToken = abi.encodePacked(callDataToToken, requestId);

        // 2. Construct the Payload.Call
        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = Payload.Call({
            to: address(mockToken),
            value: 0,
            data: callDataToToken,
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
        });

        // 3. Construct the Payload.Decoded
        Payload.Decoded memory payload = _createPayload(calls, 1, false);

        // 4. Prepare attested execution infos
        AnypayExecutionInfo[] memory attestedExecutionInfos = new AnypayExecutionInfo[](1);
        attestedExecutionInfos[0] = AnypayExecutionInfo({
            originToken: address(mockToken),
            amount: amount,
            originChainId: block.chainid,
            destinationChainId: block.chainid // Assuming same chain for now
        });

        // 5. Generate the digest to sign. This is the hash of the execution info.
        bytes32 digestToSign =
            AnypayExecutionInfoParams.getAnypayExecutionInfoHash(attestedExecutionInfos, userSignerAddress);

        // 6. Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        // 7. Encode ExecutionInfos, ECDSA signature, and signer address together
        bytes memory combinedSignature = abi.encode(attestedExecutionInfos, ecdsaSignature, userSignerAddress);

        // 8. Call recoverSapientSignature
        vm.prank(userWalletAddress);
        bytes32 actualExecutionInfoHash = signerContract.recoverSapientSignature(payload, combinedSignature);

        // 9. Assert equality
        assertEq(actualExecutionInfoHash, digestToSign, "Recovered execution info hash mismatch");
    }

    function test_RecoverSingleRelayCall_Native_ValidSignature() public {
        // 1. Prepare the call data for the relay
        uint256 amount = 2 ether;
        bytes32 requestId = keccak256("native_test_request");

        // The AnypayRelayDecoder expects just the requestId for native transfers.
        // Even though the signer does not use it, we prepare it for future compatibility.
        bytes memory callDataForRelay = abi.encode(requestId);

        // 2. Construct the Payload.Call
        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = Payload.Call({
            to: relaySolverAddress,
            value: amount,
            data: callDataForRelay,
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
        });

        // 3. Construct the Payload.Decoded
        Payload.Decoded memory payload = _createPayload(calls, 2, false);

        // 4. Prepare attested execution infos
        AnypayExecutionInfo[] memory attestedExecutionInfos = new AnypayExecutionInfo[](1);
        attestedExecutionInfos[0] = AnypayExecutionInfo({
            originToken: address(0), // address(0) for native token
            amount: amount,
            originChainId: block.chainid,
            destinationChainId: block.chainid // Assuming same chain for now
        });

        // 5. Generate the digest to sign. This is the hash of the execution info.
        bytes32 digestToSign =
            AnypayExecutionInfoParams.getAnypayExecutionInfoHash(attestedExecutionInfos, userSignerAddress);

        // 6. Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        // 7. Encode ExecutionInfos, ECDSA signature, and signer address together
        bytes memory combinedSignature = abi.encode(attestedExecutionInfos, ecdsaSignature, userSignerAddress);

        // 8. Call recoverSapientSignature
        vm.prank(userWalletAddress);
        bytes32 actualExecutionInfoHash = signerContract.recoverSapientSignature(payload, combinedSignature);

        // 9. Assert equality
        assertEq(actualExecutionInfoHash, digestToSign, "Recovered execution info hash mismatch for native call");
    }

    function test_RecoverWithApproveAndRelayCall() public {
        // 1. Prepare call data
        address spender = relaySolverAddress;
        uint256 approvalAmount = 100 ether;
        uint256 transferAmount = 50 ether;
        bytes32 requestId = keccak256("approve_and_transfer_request");

        // Call 1: Approve
        bytes memory approveCallData = abi.encodeWithSelector(bytes4(0x095ea7b3), spender, approvalAmount);

        // Call 2: Transfer to relay solver
        bytes memory transferCallData =
            abi.encodeWithSelector(MockERC20.transfer.selector, relaySolverAddress, transferAmount);
        transferCallData = abi.encodePacked(transferCallData, requestId);

        // 2. Construct Payload.Call array
        Payload.Call[] memory calls = new Payload.Call[](2);
        calls[0] = Payload.Call({
            to: address(mockToken),
            value: 0,
            data: approveCallData,
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
        });
        calls[1] = Payload.Call({
            to: address(mockToken),
            value: 0,
            data: transferCallData,
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
        });

        // 3. Construct Payload.Decoded
        Payload.Decoded memory payload = _createPayload(calls, 3, false);

        // 4. Prepare attested execution infos for both calls
        AnypayExecutionInfo[] memory attestedExecutionInfos = new AnypayExecutionInfo[](2);
        attestedExecutionInfos[0] = AnypayExecutionInfo({
            originToken: address(mockToken),
            amount: approvalAmount,
            originChainId: block.chainid,
            destinationChainId: block.chainid
        });
        attestedExecutionInfos[1] = AnypayExecutionInfo({
            originToken: address(mockToken),
            amount: transferAmount,
            originChainId: block.chainid,
            destinationChainId: block.chainid
        });

        // 5. Generate digest
        bytes32 digestToSign =
            AnypayExecutionInfoParams.getAnypayExecutionInfoHash(attestedExecutionInfos, userSignerAddress);

        // 6. Sign digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        // 7. Encode signature
        bytes memory combinedSignature = abi.encode(attestedExecutionInfos, ecdsaSignature, userSignerAddress);

        // 8. Call recoverSapientSignature
        vm.prank(userWalletAddress);
        bytes32 actualExecutionInfoHash = signerContract.recoverSapientSignature(payload, combinedSignature);

        // 9. Assert equality
        assertEq(actualExecutionInfoHash, digestToSign, "Recovered hash mismatch for approve/relay");
    }

    function test_Revert_ApproveToInvalidSpender() public {
        // 1. Prepare call data with an invalid spender
        address invalidSpender = makeAddr("invalidSpender");
        uint256 approvalAmount = 100 ether;

        bytes memory approveCallData = abi.encodeWithSelector(bytes4(0x095ea7b3), invalidSpender, approvalAmount);

        // 2. Construct Payload.Call array
        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = Payload.Call({
            to: address(mockToken),
            value: 0,
            data: approveCallData,
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
        });

        // 3. Construct Payload.Decoded
        Payload.Decoded memory payload = _createPayload(calls, 4, false);

        // 4. Prepare a valid signature for the dummy execution info
        AnypayExecutionInfo[] memory dummyInfos = new AnypayExecutionInfo[](1);
        dummyInfos[0] = AnypayExecutionInfo({
            originToken: address(mockToken),
            amount: approvalAmount,
            originChainId: block.chainid,
            destinationChainId: block.chainid
        });

        bytes32 digestToSign =
            AnypayExecutionInfoParams.getAnypayExecutionInfoHash(dummyInfos, userSignerAddress);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        bytes memory combinedSignature = abi.encode(dummyInfos, ecdsaSignature, userSignerAddress);

        // 5. Expect revert
        vm.expectRevert(AnypayRelaySapientSigner.InvalidRelayRecipient.selector);
        signerContract.recoverSapientSignature(payload, combinedSignature);
    }

    function test_DecodeSignature_Valid() public {
        // 1. Prepare execution info
        AnypayExecutionInfo[] memory executionInfos = new AnypayExecutionInfo[](1);
        executionInfos[0] = AnypayExecutionInfo({
            originToken: address(mockToken),
            amount: 1 ether,
            originChainId: 1,
            destinationChainId: 1
        });

        // 2. Prepare attestation signature
        bytes32 sampleDigest = keccak256("sample_digest");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, sampleDigest);
        bytes memory attestationSignature = abi.encodePacked(r, s, v);

        // 3. Prepare attestation signer
        address attestationSigner = userSignerAddress;

        // 4. Encode into the combined signature
        bytes memory combinedSignature = abi.encode(executionInfos, attestationSignature, attestationSigner);

        // 5. Decode the signature
        (
            AnypayExecutionInfo[] memory decodedExecutionInfos,
            bytes memory decodedAttestationSignature,
            address decodedAttestationSigner
        ) = signerContract.decodeSignature(combinedSignature);

        // 6. Assert decoded values are correct
        assertEq(decodedExecutionInfos.length, 1, "Decoded execution info count mismatch");
        assertEq(decodedExecutionInfos[0].originToken, executionInfos[0].originToken, "Decoded origin token mismatch");
        assertEq(decodedExecutionInfos[0].amount, executionInfos[0].amount, "Decoded amount mismatch");
        assertEq(decodedExecutionInfos[0].originChainId, executionInfos[0].originChainId, "Decoded origin chain ID mismatch");
        assertEq(
            decodedExecutionInfos[0].destinationChainId,
            executionInfos[0].destinationChainId,
            "Decoded destination chain ID mismatch"
        );
        assertEq(decodedAttestationSignature, attestationSignature, "Decoded attestation signature mismatch");
        assertEq(decodedAttestationSigner, attestationSigner, "Decoded attestation signer mismatch");
    }

    function test_Revert_DecodeSignature_Empty() public {
        bytes memory emptySignature = "";
        vm.expectRevert(AnypayRelaySapientSigner.InvalidSignatureLength.selector);
        signerContract.decodeSignature(emptySignature);
    }

    function test_Revert_DecodeSignature_Malformed() public {
        bytes memory malformedSignature = hex"0123456789abcdef";
        vm.expectRevert(AnypayRelaySapientSigner.InvalidSignatureLength.selector);
        signerContract.decodeSignature(malformedSignature);
    }

    function test_DecodeSignature_MalformedFromUser() public {
        bytes memory malformedSignature =
            hex"000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda02913000000000000000000000000000000000000000000000000000000000014856a0000000000000000000000000000000000000000000000000000000000002105000000000000000000000000000000000000000000000000000000000000a4b1";
        signerContract.decodeSignature(malformedSignature);
    }

    // Helper to construct Payload.Decoded more easily if needed later
    function _createPayload(Payload.Call[] memory _calls, uint256 _nonce, bool _noChainId)
        internal
        pure
        returns (Payload.Decoded memory)
    {
        return Payload.Decoded({
            kind: Payload.KIND_TRANSACTIONS,
            noChainId: _noChainId,
            calls: _calls,
            space: 0,
            nonce: _nonce,
            message: "",
            imageHash: bytes32(0),
            digest: bytes32(0),
            parentWallets: new address[](0)
        });
    }
}
