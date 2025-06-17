// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {AnypayRelaySapientSigner} from "@/AnypayRelaySapientSigner.sol";
import {AnypayRelayInfo} from "@/interfaces/AnypayRelay.sol";
import {AnypayRelayDecoder} from "@/libraries/AnypayRelayDecoder.sol";

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

        // Sample relay info
        AnypayRelayInfo memory info = AnypayRelayInfo({
            requestId: bytes32("requestId"),
            signature: new bytes(0),
            nonEVMReceiver: bytes32("nonEVMReceiver"),
            receivingAssetId: bytes32("receivingAssetId"),
            sendingAssetId: address(0x2),
            receiver: address(0x3),
            destinationChainId: 1,
            minAmount: 100,
            target: address(0x4)
        });

        // Sample payload
        bytes memory callData = abi.encode(info.requestId);

        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = Payload.Call({
            to: info.target,
            value: 0,
            data: abi.encodePacked(bytes4(0xa9059cbb), abi.encode(info.receiver, info.minAmount, info.requestId)),
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: 0
        });

        calls[0].to = info.sendingAssetId;

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
        // We need to adjust the payload to match the attested info
        payload.calls[0].to = attestedRelayInfos[0].sendingAssetId;
        payload.calls[0].data = abi.encodePacked(
            bytes4(0xa9059cbb),
            abi.encode(
                attestedRelayInfos[0].receiver, attestedRelayInfos[0].minAmount, attestedRelayInfos[0].requestId
            )
        );

        bytes memory encodedSignature = createEncodedSignature(attestedRelayInfos, signer);

        vm.prank(userWalletAddress);
        bytes32 result = anypayRelaySapientSigner.recoverSapientSignature(payload, encodedSignature);

        bytes32 expectedHash = keccak256(abi.encode(attestedRelayInfos, signer));
        assertEq(result, expectedHash);
        console.log("AnypayRelaySapientSigner.recoverSapientSignature an successfully recovered sapient signature");
    }

    function testRevert_whenInvalidAttestationSigner() public {
        address wrongSigner = address(0xdead);
        bytes memory encodedSignature = createEncodedSignature(attestedRelayInfos, wrongSigner);

        vm.prank(userWalletAddress);
        vm.expectRevert(
            abi.encodeWithSelector(
                AnypayRelaySapientSigner.InvalidAttestationSigner.selector, wrongSigner, signer
            )
        );
        anypayRelaySapientSigner.recoverSapientSignature(payload, encodedSignature);
    }

    function testRevert_whenEmptyRelayInfos() public {
        AnypayRelayInfo[] memory emptyInfos = new AnypayRelayInfo[](0);
        bytes memory encodedSignature = createEncodedSignature(emptyInfos, signer);

        vm.prank(userWalletAddress);
        vm.expectRevert(abi.encodeWithSelector(AnypayRelaySapientSigner.MismatchedRelayInfoLengths.selector));
        anypayRelaySapientSigner.recoverSapientSignature(payload, encodedSignature);
    }

    function testRevert_whenInvalidRelayQuote() public {
        // Tamper with the signature
        attestedRelayInfos[0].signature[5] = 0x00;
        bytes memory encodedSignature = createEncodedSignature(attestedRelayInfos, signer);

        vm.prank(userWalletAddress);
        vm.expectRevert(abi.encodeWithSelector(AnypayRelaySapientSigner.InvalidRelayQuote.selector));
        anypayRelaySapientSigner.recoverSapientSignature(payload, encodedSignature);
    }

    function test_decodeSignature() public {
        bytes memory encodedSignature = createEncodedSignature(attestedRelayInfos, signer);
        (AnypayRelayInfo[] memory decodedRelayInfos, bytes memory attestationSignature, address attestationSigner) =
            anypayRelaySapientSigner.decodeSignature(encodedSignature);

        bytes32 payloadHash = payload.hashFor(userWalletAddress);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, payloadHash);
        bytes memory expectedAttestationSignature = abi.encodePacked(r, s, v);

        assertEq(attestationSignature, expectedAttestationSignature);
        assertEq(decodedRelayInfos.length, attestedRelayInfos.length);
        assertEq(decodedRelayInfos[0].requestId, attestedRelayInfos[0].requestId);
        assertEq(attestationSigner, signer);
    }

    function createEncodedSignature(AnypayRelayInfo[] memory infos, address _signer)
        internal
        view
        returns (bytes memory)
    {
        bytes32 payloadHash = payload.hashFor(userWalletAddress);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, payloadHash);
        bytes memory attestationSignature = abi.encodePacked(r, s, v);

        return abi.encode(infos, attestationSignature, _signer);
    }
}
