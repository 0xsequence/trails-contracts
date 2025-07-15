// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {TrailsCCTPV2SapientSigner} from "@/TrailsCCTPV2SapientSigner.sol";
import {TrailsExecutionInfo} from "@/interfaces/TrailsExecutionInfo.sol";
import {CCTPExecutionInfo, ITokenMessengerV2} from "@/interfaces/TrailsCCTPV2.sol";
import {TrailsCCTPUtils} from "@/libraries/TrailsCCTPUtils.sol";
import {TrailsExecutionInfoParams} from "@/libraries/TrailsExecutionInfoParams.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract TrailsCCTPV2SapientSignerTest is Test {
    using MessageHashUtils for bytes32;

    uint256 internal constant FORK_CHAIN_ID = 1;

    TrailsCCTPV2SapientSigner public signer;
    MockERC20 public usdc;
    address public tokenMessenger;
    uint256 internal attestPrivateKey;
    address internal attestSigner;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        tokenMessenger = address(0x123); // Mock address
        signer = new TrailsCCTPV2SapientSigner(tokenMessenger);
        (attestSigner, attestPrivateKey) = makeAddrAndKey("attestSigner");
    }

    function test_recoverSapientSignature_valid() public view {
        // 1. Attestation Data
        uint32 destinationDomain = 6; // Arbitrum
        TrailsExecutionInfo[] memory attestedExecutionInfos = new TrailsExecutionInfo[](1);
        attestedExecutionInfos[0] = TrailsExecutionInfo({
            originToken: address(usdc),
            amount: 1_000_000,
            originChainId: FORK_CHAIN_ID,
            destinationChainId: TrailsCCTPUtils.cctpDomainToChainId(destinationDomain)
        });

        // 2. Payload Data (to be signed by wallet)
        bytes memory mintRecipient = abi.encode(attestSigner);
        bytes32 nonce = bytes32(uint256(123));

        bytes memory callData = abi.encodeWithSelector(
            ITokenMessengerV2.depositForBurnWithHook.selector,
            attestedExecutionInfos[0].amount,
            destinationDomain,
            mintRecipient,
            address(usdc),
            address(0), // remoteForwarder
            attestSigner,
            nonce,
            "" // hookCalldata
        );

        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = Payload.Call({
            to: tokenMessenger,
            value: 0,
            data: callData,
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: 1
        });

        Payload.Decoded memory payload = Payload.Decoded({
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

        // 3. Create Signatures
        bytes32 payloadHash = Payload.hashFor(payload, address(0)).toEthSignedMessageHash();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attestPrivateKey, payloadHash);
        bytes memory attestationSignature = abi.encodePacked(r, s, v);

        bytes memory encodedSignature = abi.encode(attestedExecutionInfos, attestationSignature, attestSigner);

        // 4. Recover and verify
        bytes32 expectedDigest =
            TrailsExecutionInfoParams.getTrailsExecutionInfoHash(attestedExecutionInfos, attestSigner);
        bytes32 recoveredDigest = signer.recoverSapientSignature(payload, encodedSignature);

        assertEq(recoveredDigest, expectedDigest);
    }

    function test_revert_when_payload_kind_is_not_transactions() public {
        Payload.Decoded memory payload = Payload.Decoded({
            kind: Payload.KIND_MESSAGE, // Invalid kind
            noChainId: false,
            calls: new Payload.Call[](0),
            space: 0,
            nonce: 0,
            message: "test",
            imageHash: bytes32(0),
            digest: bytes32(0),
            parentWallets: new address[](0)
        });
        vm.expectRevert(TrailsCCTPV2SapientSigner.InvalidPayloadKind.selector);
        signer.recoverSapientSignature(payload, "");
    }

    function test_revert_when_calls_is_empty() public {
        Payload.Decoded memory payload = Payload.Decoded({
            kind: Payload.KIND_TRANSACTIONS,
            noChainId: false,
            calls: new Payload.Call[](0), // Empty calls
            space: 0,
            nonce: 0,
            message: "",
            imageHash: bytes32(0),
            digest: bytes32(0),
            parentWallets: new address[](0)
        });
        vm.expectRevert(TrailsCCTPV2SapientSigner.InvalidCallsLength.selector);
        signer.recoverSapientSignature(payload, "");
    }

    function test_revert_with_invalid_target_address() public {
        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = Payload.Call({
            to: address(0xdead), // Invalid target
            value: 0,
            data: "",
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: 1
        });
        Payload.Decoded memory payload = Payload.Decoded({
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
        vm.expectRevert(
            abi.encodeWithSelector(
                TrailsCCTPV2SapientSigner.InvalidTargetAddress.selector, tokenMessenger, address(0xdead)
            )
        );
        signer.recoverSapientSignature(payload, "");
    }
}
