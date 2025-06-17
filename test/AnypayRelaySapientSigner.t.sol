// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {AnypayRelaySapientSigner} from "@/AnypayRelaySapientSigner.sol";
import {AnypayRelayInfo} from "@/interfaces/AnypayRelay.sol";

contract AnypayRelaySapientSignerTest is Test {
    using ECDSA for bytes32;
    using Payload for Payload.Decoded;

    AnypayRelaySapientSigner internal anypayRelaySapientSigner;
    uint256 internal signerPrivateKey = 0x1234;
    address internal signer = vm.addr(signerPrivateKey);
    uint256 internal relaySolverPrivateKey = 0x5678;
    address internal relaySolver = vm.addr(relaySolverPrivateKey);
    address internal userWalletAddress;

    Payload.Decoded internal payload;
    AnypayRelayInfo[] internal attestedRelayInfos;

    function setUp() public {
        userWalletAddress = address(this);
        anypayRelaySapientSigner = new AnypayRelaySapientSigner(relaySolver);

        // Sample payload
        address target = address(0x1);
        bytes memory callData = abi.encode("callData");

        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = Payload.Call({
            to: target,
            value: 0,
            data: callData,
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: 0
        });

        payload = Payload.Decoded({
            kind: Payload.KIND_TRANSACTIONS,
            noChainId: false,
            calls: calls,
            space: 0,
            nonce: 0,
            message: "",
            imageHash: bytes32(0),
            digest: bytes32(0),
            parentWallets: new address[](0)
        });

        // Sample relay info
        AnypayRelayInfo memory info = AnypayRelayInfo({
            requestId: "requestId",
            signature: new bytes(0),
            nonEVMReceiver: "nonEVMReceiver",
            receivingAssetId: "receivingAssetId",
            sendingAssetId: address(0x2),
            receiver: address(0x3),
            destinationChainId: 1,
            minAmount: 100,
            target: address(0x4)
        });

        bytes32 message = keccak256(
            abi.encodePacked(
                info.requestId,
                block.chainid,
                bytes32(uint256(uint160(info.target))),
                bytes32(uint256(uint160(info.sendingAssetId))),
                info.destinationChainId,
                info.receiver == anypayRelaySapientSigner.NON_EVM_ADDRESS()
                    ? info.nonEVMReceiver
                    : bytes32(uint256(uint160(info.receiver))),
                info.receivingAssetId
            )
        );

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(relaySolverPrivateKey, keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", message)));
        info.signature = abi.encodePacked(r, s, v);

        attestedRelayInfos = new AnypayRelayInfo[](1);
        attestedRelayInfos[0] = info;
    }

    function test_recoverSapientSignature_succeeds() public {
        bytes memory encodedSignature = createEncodedSignature(attestedRelayInfos);

        vm.prank(userWalletAddress);
        bytes32 result = anypayRelaySapientSigner.recoverSapientSignature(payload, encodedSignature);

        bytes32 expectedHash = keccak256(abi.encode(attestedRelayInfos, signer));
        assertEq(result, expectedHash);
    }

    function testRevert_whenInvalidAttestationSigner() public {
        bytes memory wrongSig = "wrong signature";
        bytes memory encodedSignature = abi.encode(wrongSig, attestedRelayInfos);

        vm.prank(userWalletAddress);
        vm.expectRevert("InvalidSignature()");
        anypayRelaySapientSigner.recoverSapientSignature(payload, encodedSignature);
    }

    function testRevert_whenEmptyRelayInfos() public {
        AnypayRelayInfo[] memory emptyInfos = new AnypayRelayInfo[](0);
        bytes memory encodedSignature = createEncodedSignature(emptyInfos);

        vm.prank(userWalletAddress);
        vm.expectRevert(abi.encodeWithSelector(AnypayRelaySapientSigner.MismatchedRelayInfoLengths.selector));
        anypayRelaySapientSigner.recoverSapientSignature(payload, encodedSignature);
    }

    function testRevert_whenInvalidRelayQuote() public {
        // Tamper with the signature
        attestedRelayInfos[0].signature[5] = 0x00;
        bytes memory encodedSignature = createEncodedSignature(attestedRelayInfos);

        vm.prank(userWalletAddress);
        vm.expectRevert(abi.encodeWithSelector(AnypayRelaySapientSigner.InvalidRelayQuote.selector));
        anypayRelaySapientSigner.recoverSapientSignature(payload, encodedSignature);
    }

    function test_decodeSignature() public {
        bytes memory encodedSignature = createEncodedSignature(attestedRelayInfos);
        (bytes memory attestationSignature, AnypayRelayInfo[] memory decodedRelayInfos) =
            anypayRelaySapientSigner.decodeSignature(encodedSignature);

        bytes32 payloadHash = payload.hashFor(userWalletAddress);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, payloadHash);
        bytes memory expectedAttestationSignature = abi.encodePacked(r, s, v);

        assertEq(attestationSignature, expectedAttestationSignature);
        assertEq(decodedRelayInfos.length, attestedRelayInfos.length);
        assertEq(decodedRelayInfos[0].requestId, attestedRelayInfos[0].requestId);
    }

    function createEncodedSignature(AnypayRelayInfo[] memory infos) internal view returns (bytes memory) {
        bytes32 payloadHash = payload.hashFor(userWalletAddress);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, payloadHash);
        bytes memory attestationSignature = abi.encodePacked(r, s, v);

        return abi.encode(attestationSignature, infos);
    }
}
