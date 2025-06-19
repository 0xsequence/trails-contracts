// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {AnypayRelaySapientSigner} from "@/AnypayRelaySapientSigner.sol";
import {AnypayExecutionInfo} from "@/interfaces/AnypayExecutionInfo.sol";
import {AnypayExecutionInfoParams} from "@/libraries/AnypayExecutionInfoParams.sol";

// Mock ERC20 contract for testing transfers
contract MockERC20 is Test {
    function transfer(address to, uint256 amount) external returns (bool) {
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
        address receiver = makeAddr("receiver");
        uint256 amount = 1 ether;

        // This would be the data for an ERC20 transfer call in a real scenario
        bytes memory callDataToToken = abi.encodeWithSelector(MockERC20.transfer.selector, receiver, amount);

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

        // 4. Generate the EIP-712 digest.
        bytes32 digestToSign = payload.hashFor(userWalletAddress);

        // 5. Prepare attested execution infos
        AnypayExecutionInfo[] memory attestedExecutionInfos = new AnypayExecutionInfo[](1);
        attestedExecutionInfos[0] = AnypayExecutionInfo({
            originToken: address(mockToken),
            amount: amount,
            originChainId: block.chainid,
            destinationChainId: block.chainid // Assuming same chain for now
        });

        // 6. Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        // 7. Encode ExecutionInfos, ECDSA signature, and signer address together
        bytes memory combinedSignature = abi.encode(attestedExecutionInfos, ecdsaSignature, userSignerAddress);

        // 8. Manually derive the expected executionInfoHash
        bytes32 expectedExecutionInfoHash =
            AnypayExecutionInfoParams.getAnypayExecutionInfoHash(attestedExecutionInfos, userSignerAddress);

        // 9. Call recoverSapientSignature
        vm.prank(userWalletAddress);
        bytes32 actualExecutionInfoHash = signerContract.recoverSapientSignature(payload, combinedSignature);

        // 10. Assert equality
        assertEq(actualExecutionInfoHash, expectedExecutionInfoHash, "Recovered execution info hash mismatch");
    }

    function test_RecoverSingleRelayCall_Native_ValidSignature() public {
        // 1. Prepare the call data for the relay
        address receiver = makeAddr("receiver");
        uint256 amount = 2 ether;
        bytes32 requestId = keccak256("native_test_request");

        // The AnypayRelayDecoder expects just the requestId for native transfers.
        // Even though the signer does not use it, we prepare it for future compatibility.
        bytes memory callDataForRelay = abi.encode(requestId);

        // 2. Construct the Payload.Call
        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = Payload.Call({
            to: receiver,
            value: amount,
            data: callDataForRelay,
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
        });

        // 3. Construct the Payload.Decoded
        Payload.Decoded memory payload = _createPayload(calls, 2, false);

        // 4. Generate the EIP-712 digest.
        bytes32 digestToSign = payload.hashFor(userWalletAddress);

        // 5. Prepare attested execution infos
        AnypayExecutionInfo[] memory attestedExecutionInfos = new AnypayExecutionInfo[](1);
        attestedExecutionInfos[0] = AnypayExecutionInfo({
            originToken: address(0), // address(0) for native token
            amount: amount,
            originChainId: block.chainid,
            destinationChainId: block.chainid // Assuming same chain for now
        });

        // 6. Sign the digest
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userSignerPrivateKey, digestToSign);
        bytes memory ecdsaSignature = abi.encodePacked(r, s, v);

        // 7. Encode ExecutionInfos, ECDSA signature, and signer address together
        bytes memory combinedSignature = abi.encode(attestedExecutionInfos, ecdsaSignature, userSignerAddress);

        // 8. Manually derive the expected executionInfoHash
        bytes32 expectedExecutionInfoHash =
            AnypayExecutionInfoParams.getAnypayExecutionInfoHash(attestedExecutionInfos, userSignerAddress);

        // 9. Call recoverSapientSignature
        vm.prank(userWalletAddress);
        bytes32 actualExecutionInfoHash = signerContract.recoverSapientSignature(payload, combinedSignature);

        // 10. Assert equality
        assertEq(
            actualExecutionInfoHash,
            expectedExecutionInfoHash,
            "Recovered execution info hash mismatch for native call"
        );
    }

    // Helper to construct Payload.Decoded more easily if needed later
    function _createPayload(Payload.Call[] memory _calls, uint256 _nonce, bool _noChainId)
        internal
        view
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