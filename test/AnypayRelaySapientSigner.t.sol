// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {AnypayRelaySapientSigner} from "@/AnypayRelaySapientSigner.sol";
import {AnypayExecutionInfo} from "@/interfaces/AnypayExecutionInfo.sol";
import {AnypayExecutionInfoParams} from "@/libraries/AnypayExecutionInfoParams.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";

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
        signerContract = new AnypayRelaySapientSigner();

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

        // 5. Generate the digest to sign. This is the hash of the payload.
        bytes32 digestToSign = payload.hashFor(userWalletAddress);

        // 6. Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        // 7. Encode ExecutionInfos, ECDSA signature, and signer address together
        bytes memory combinedSignature = abi.encode(attestedExecutionInfos, ecdsaSignature, userSignerAddress);

        // 8. Call recoverSapientSignature
        vm.prank(userWalletAddress);
        bytes32 actualExecutionInfoHash = signerContract.recoverSapientSignature(payload, combinedSignature);

        // 9. Assert equality against the manually calculated hash
        bytes32 expectedExecutionInfoHash =
            AnypayExecutionInfoParams.getAnypayExecutionInfoHash(attestedExecutionInfos, userSignerAddress);
        assertEq(actualExecutionInfoHash, expectedExecutionInfoHash, "Recovered execution info hash mismatch");
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

        // 5. Generate the digest to sign. This is the hash of the payload.
        bytes32 digestToSign = payload.hashFor(userWalletAddress);

        // 6. Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        // 7. Encode ExecutionInfos, ECDSA signature, and signer address together
        bytes memory combinedSignature = abi.encode(attestedExecutionInfos, ecdsaSignature, userSignerAddress);

        // 8. Call recoverSapientSignature
        vm.prank(userWalletAddress);
        bytes32 actualExecutionInfoHash = signerContract.recoverSapientSignature(payload, combinedSignature);

        // 9. Assert equality against the manually calculated hash
        bytes32 expectedExecutionInfoHash =
            AnypayExecutionInfoParams.getAnypayExecutionInfoHash(attestedExecutionInfos, userSignerAddress);
        assertEq(
            actualExecutionInfoHash, expectedExecutionInfoHash, "Recovered execution info hash mismatch for native call"
        );
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
        bytes32 digestToSign = payload.hashFor(userWalletAddress);

        // 6. Sign digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        // 7. Encode signature
        bytes memory combinedSignature = abi.encode(attestedExecutionInfos, ecdsaSignature, userSignerAddress);

        // 8. Call recoverSapientSignature
        vm.prank(userWalletAddress);
        bytes32 actualExecutionInfoHash = signerContract.recoverSapientSignature(payload, combinedSignature);

        // 9. Assert equality
        bytes32 expectedExecutionInfoHash =
            AnypayExecutionInfoParams.getAnypayExecutionInfoHash(attestedExecutionInfos, userSignerAddress);
        assertEq(actualExecutionInfoHash, expectedExecutionInfoHash, "Recovered hash mismatch for approve/relay");
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

        bytes32 digestToSign = AnypayExecutionInfoParams.getAnypayExecutionInfoHash(dummyInfos, userSignerAddress);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        bytes memory combinedSignature = abi.encode(dummyInfos, ecdsaSignature, userSignerAddress);

        // 5. Expect revert
        vm.expectRevert(AnypayRelaySapientSigner.InvalidRelayRecipient.selector);
        signerContract.recoverSapientSignature(payload, combinedSignature);
    }

    function test_HardcodedSignature() public view {
        bytes memory hardcodedSignature =
            hex"00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000100000000000000000000000000e7dfe7c72b4b58ac6b64614f7417ac296134a9740000000000000000000000000000000000000000000000000000000000000001000000000000000000000000fde4c96c8593536e31f229ea8f37b2ada2699bb200000000000000000000000000000000000000000000000000000000000918d40000000000000000000000000000000000000000000000000000000000002105000000000000000000000000000000000000000000000000000000000000a4b1000000000000000000000000000000000000000000000000000000000000004140bb829e761ff58b55d09c406e7ab968e526db3790dda8c53818f9340006118506061a7cd65d5ea4404172c82ffe5eb23d05b01656a26e22635e74b572dc07b30000000000000000000000000000000000000000000000000000000000000000";
        (AnypayExecutionInfo[] memory executionInfos, bytes memory attestationSignature, address attestationSigner) =
            signerContract.decodeSignature(hardcodedSignature);

        // Log execution infos
        for (uint256 i = 0; i < executionInfos.length; i++) {
            console.log("Execution info", i);
            console.log("Origin token", executionInfos[i].originToken);
            console.log("Amount", executionInfos[i].amount);
            console.log("Origin chain id", executionInfos[i].originChainId);
        }
        console.log("Attestation signer", attestationSigner);

        assertEq(executionInfos.length, 1, "Execution info count mismatch");
        assertEq(attestationSignature.length, 65, "Attestation signature length mismatch");
        // assertEq(attestationSigner, 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2, "Attestation signer mismatch");
    }

    function test_RecoverSingleRelayCall_ERC20_ValidAttestation() public {
        // 1. Prepare call data
        address receiver = relaySolverAddress;
        uint256 amount = 1 ether;
        bytes32 requestId = keccak256("erc20_test_request");
        bytes memory callDataToToken = abi.encodeWithSelector(MockERC20.transfer.selector, receiver, amount);
        callDataToToken = abi.encodePacked(callDataToToken, requestId);

        // 2. Construct Payload
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
        Payload.Decoded memory payload = _createPayload(calls, 1, false);

        // 3. Generate EIP-712 digest of payload
        bytes32 digestToSign = payload.hashFor(userWalletAddress);

        // 4. Prepare attested execution info
        AnypayExecutionInfo[] memory attestedExecutionInfos = new AnypayExecutionInfo[](1);
        attestedExecutionInfos[0] = AnypayExecutionInfo({
            originToken: address(mockToken),
            amount: amount,
            originChainId: 1,
            destinationChainId: 1
        });

        // 5. Sign the payload digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory attestationSignature = abi.encodePacked(r, s, v);

        // 6. Encode the combined signature for the sapient module
        bytes memory combinedSignature = abi.encode(attestedExecutionInfos, attestationSignature, userSignerAddress);

        // 7. Calculate the expected hash of the attestation, which the module should return
        bytes32 expectedAttestationHash =
            AnypayExecutionInfoParams.getAnypayExecutionInfoHash(attestedExecutionInfos, userSignerAddress);

        // 8. Recover and verify
        vm.prank(userWalletAddress);
        bytes32 actualAttestationHash = signerContract.recoverSapientSignature(payload, combinedSignature);
        assertEq(actualAttestationHash, expectedAttestationHash, "Recovered attestation hash mismatch");
    }

    function test_RecoverSingleRelayCall_Native_ValidAttestation() public {
        // 1. Prepare call data
        uint256 amount = 2 ether;
        bytes32 requestId = keccak256("native_test_request");
        bytes memory callDataForRelay = abi.encode(requestId);

        // 2. Construct Payload
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
        Payload.Decoded memory payload = _createPayload(calls, 2, false);

        // 3. Generate EIP-712 digest of payload
        bytes32 digestToSign = payload.hashFor(userWalletAddress);

        // 4. Prepare attested execution info
        AnypayExecutionInfo[] memory attestedExecutionInfos = new AnypayExecutionInfo[](1);
        attestedExecutionInfos[0] =
            AnypayExecutionInfo({originToken: address(0), amount: amount, originChainId: 1, destinationChainId: 1});

        // 5. Sign the payload digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory attestationSignature = abi.encodePacked(r, s, v);

        // 6. Encode the combined signature for the sapient module
        bytes memory combinedSignature = abi.encode(attestedExecutionInfos, attestationSignature, userSignerAddress);

        // 7. Calculate expected hash of the attestation
        bytes32 expectedAttestationHash =
            AnypayExecutionInfoParams.getAnypayExecutionInfoHash(attestedExecutionInfos, userSignerAddress);

        // 8. Recover and verify
        vm.prank(userWalletAddress);
        bytes32 actualAttestationHash = signerContract.recoverSapientSignature(payload, combinedSignature);
        assertEq(actualAttestationHash, expectedAttestationHash, "Recovered attestation hash mismatch for native call");
    }

    function test_recoverSapientSignature_failing_from_user() public {
        // This test case is based on a failing transaction reported by a user.
        // It's designed to replicate the exact conditions of that failure for debugging.

        // In the real scenario, the AnypayRelaySapientSigner is configured with the true
        // RELAY_SOLVER address, not the intermediate RelayReceiver contract address.
        AnypayRelaySapientSigner signerContractForThisTest = new AnypayRelaySapientSigner();

        // Recreate the payload from the user's report. The `to` address is the RelayReceiver contract.
        // `_payload = {"kind":0,"noChainId":false,"calls":[{"to":"0xa5f565650890fba1824ee0f21ebbbf660a179934","value":"13835264386605673","data":"0x77245ba68c303ba96be68543927984459fc317401ddbb7277257ba12a31a8205","gasLimit":"0","delegateCall":false,"onlyFallback":false,"behaviorOnError":"0"}],"space":"0","nonce":"0","message":"0x","imageHash":"0x0000000000000000000000000000000000000000000000000000000000000000","digest":"0x0000000000000000000000000000000000000000000000000000000000000000","parentWallets":[]}`
        Payload.Decoded memory payload;
        payload.kind = Payload.KIND_TRANSACTIONS;

        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = Payload.Call({
            to: 0xa5F565650890fBA1824Ee0F21EbBbF660a179934,
            value: 13835264386605673,
            data: hex"77245ba68c303ba96be68543927984459fc317401ddbb7277257ba12a31a8205",
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
        });
        payload.calls = calls;

        // The signature provided by the user.
        bytes memory signature =
            hex"000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005a5f48f2ce4f60000000000000000000000000000000000000000000000000000000000002105000000000000000000000000000000000000000000000000000000000000a4b1000000000000000000000000000000000000000000000000000000000000004163a63ea74e87618e93ae6d9a633fe006248d5e4608d9b9ea73a27f46771ff03a3de7b677a69b6e3632818474b1e86e2f97e9f9d6446c495d2ea27f9800902bef0000000000000000000000000000000000000000000000000000000000000000";

        (
            AnypayExecutionInfo[] memory attestedExecutionInfos,
            , // ecdsaSignature not needed
            address expectedSigner
        ) = signerContractForThisTest.decodeSignature(signature);

        bytes32 digestToSign =
            AnypayExecutionInfoParams.getAnypayExecutionInfoHash(attestedExecutionInfos, expectedSigner);
        console.logBytes32(digestToSign);

        // TODO: Fix this test
        // bytes32 actualExecutionInfoHash = signerContractForThisTest.recoverSapientSignature(payload, signature);
        // assertEq(actualExecutionInfoHash, digestToSign);
    }

    function test_recoverSapientSignature_revert_from_trace() public {
        AnypayRelaySapientSigner signer = new AnypayRelaySapientSigner();

        Payload.Decoded memory payload;
        payload.kind = Payload.KIND_TRANSACTIONS;

        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = Payload.Call({
            to: 0x0D8775F648430679A709E98d2b0Cb6250d2887EF,
            value: 0,
            data: hex"095ea7b3000000000000000000000000aaaaaaae92cc1ceef79a038017889fdd26d23d4d0000000000000000000000000000000000000000000000000717fd85436c896b",
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
        });
        payload.calls = calls;

        bytes memory encodedSignature =
            hex"00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000d8775f648430679a709e98d2b0cb6250d2887ef00000000000000000000000000000000000000000000000053444835ec5800000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000a4b100000000000000000000000000000000000000000000000000000000000000414f3f5fe2c5f92714a03af63036d46c05aba9fd888be3083ac541cf79c440b4d053b0dec5dcb50cdc0252915da40304f4f527fc636297afc4aa8fa83463fdfe080100000000000000000000000000000000000000000000000000000000000000";

        signer.recoverSapientSignature(payload, encodedSignature);
    }

    function testUserProvidedSignature() public view {
        bytes memory userSignature =
            hex"00000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000100000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb922660000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000021b9fc72d0e160000000000000000000000000000000000000000000000000000000000002105000000000000000000000000000000000000000000000000000000000000a4b100000000000000000000000000000000000000000000000000000000000000416aca808b75ecbdf1d0a7639d438bf1352cfb21a935e468504e456e176cfca7ff6b5c4c77b8ae705f5ba5e6c46d0cbdbfbdfab62ca06fae1c401629e15e07da2a1c00000000000000000000000000000000000000000000000000000000000000";
        (AnypayExecutionInfo[] memory executionInfos, bytes memory attestationSignature, address attestationSigner) =
            signerContract.decodeSignature(userSignature);

        console.log("--- User Provided Signature Test ---");
        for (uint256 i = 0; i < executionInfos.length; i++) {
            console.log("Execution info", i);
            console.log("Origin token", executionInfos[i].originToken);
            console.log("Amount", executionInfos[i].amount);
            console.log("Origin chain id", executionInfos[i].originChainId);
            console.log("Destination chain id", executionInfos[i].destinationChainId);
        }
        console.logBytes(attestationSignature);
        console.log("Attestation signer", attestationSigner);
        console.log("--- End User Provided Signature Test ---");

        assertEq(executionInfos.length, 1, "Execution info count mismatch");
        assertEq(executionInfos[0].originToken, address(0), "Decoded originToken mismatch");
        // assertEq(
        //     executionInfos[0].amount, 243000000000000000, "Decoded amount mismatch"
        // );
        assertEq(executionInfos[0].originChainId, 8453, "Decoded originChainId mismatch");
        assertEq(executionInfos[0].destinationChainId, 42161, "Decoded destinationChainId mismatch");
        assertEq(attestationSignature.length, 65, "Attestation signature length mismatch");
        assertEq(attestationSigner, 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, "Decoded attestationSigner mismatch");
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
