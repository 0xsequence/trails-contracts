// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {AnypayRelayParams} from "@/libraries/AnypayRelayParams.sol";
import {AnypayRelayInfo} from "@/interfaces/AnypayRelay.sol";

contract AnypayRelayParamsTest is Test {
    AnypayRelayParams.IntentParamsData internal baseParams;
    AnypayRelayInfo[] internal relayInfos;
    address internal attestationAddress;
    Payload.Call internal sampleCall;

    function setUp() public {
        sampleCall = Payload.Call({
            to: address(0x00000000000000000000000000000000000000B1),
            value: 1 ether,
            data: hex"aabbcc",
            gasLimit: 21000,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: 0
        });

        baseParams.userAddress = address(0x1234567890123456789012345678901234567890);
        baseParams.nonce = 0;

        baseParams.originTokens = new AnypayRelayParams.OriginToken[](1);
        baseParams.originTokens[0] = AnypayRelayParams.OriginToken({
            tokenAddress: address(0x00000000000000000000000000000000000000A1),
            chainId: 1
        });

        baseParams.destinationCalls = new Payload.Decoded[](1);
        Payload.Call[] memory callsForDest0 = new Payload.Call[](1);
        callsForDest0[0] = sampleCall;
        baseParams.destinationCalls[0] = Payload.Decoded({
            kind: Payload.KIND_TRANSACTIONS,
            noChainId: false,
            calls: callsForDest0,
            space: 0,
            nonce: 0,
            message: "",
            imageHash: bytes32(0),
            digest: bytes32(0),
            parentWallets: new address[](0)
        });

        baseParams.destinationTokens = new AnypayRelayParams.DestinationToken[](1);
        baseParams.destinationTokens[0] = AnypayRelayParams.DestinationToken({
            tokenAddress: address(0x00000000000000000000000000000000000000C1),
            chainId: 1,
            amount: 2 ether
        });

        relayInfos = new AnypayRelayInfo[](1);
        relayInfos[0] = AnypayRelayInfo({
            requestId: 0x0000000000000000000000000000000000000000000000000000000000000001,
            signature: hex"abcd",
            nonEVMReceiver: 0x0000000000000000000000000000000000000000000000000000000000000002,
            receivingAssetId: 0x0000000000000000000000000000000000000000000000000000000000000003,
            sendingAssetId: 0x5555555555555555555555555555555555555555,
            receiver: 0x6666666666666666666666666666666666666666,
            destinationChainId: 137,
            minAmount: 1000,
            target: 0x7777777777777777777777777777777777777777
        });

        attestationAddress = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;
    }

    function testHashRelayIntent_HappyPath() public {
        vm.chainId(1);
        bytes32 hash = AnypayRelayParams.hashRelayIntent(baseParams, relayInfos, attestationAddress);
        // This is a snapshot of the expected hash. If the hashing logic changes, this value needs to be updated.
        bytes32 expectedHash = 0x49dd1098e3810e6981be3bbe34f6beb6d5ac7e7bd85b58e4f7569890fbdace8c;
        assertEq(hash, expectedHash, "Relay intent hash mismatch");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfUserAddressIsZero() public {
        baseParams.userAddress = address(0);
        vm.expectRevert(AnypayRelayParams.UserAddressIsZero.selector);
        AnypayRelayParams.hashRelayIntent(baseParams, relayInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfOriginTokensIsEmpty() public {
        baseParams.originTokens = new AnypayRelayParams.OriginToken[](0);
        vm.expectRevert(AnypayRelayParams.OriginTokensIsEmpty.selector);
        AnypayRelayParams.hashRelayIntent(baseParams, relayInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfDestinationCallsIsEmpty() public {
        baseParams.destinationCalls = new Payload.Decoded[](0);
        vm.expectRevert(AnypayRelayParams.DestinationCallsIsEmpty.selector);
        AnypayRelayParams.hashRelayIntent(baseParams, relayInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfDestinationTokensIsEmpty() public {
        baseParams.destinationTokens = new AnypayRelayParams.DestinationToken[](0);
        vm.expectRevert(AnypayRelayParams.DestinationTokensIsEmpty.selector);
        AnypayRelayParams.hashRelayIntent(baseParams, relayInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfDestinationCallKindIsNotTransactions() public {
        baseParams.destinationCalls[0].kind = Payload.KIND_MESSAGE;
        vm.expectRevert(AnypayRelayParams.InvalidDestinationCallKind.selector);
        AnypayRelayParams.hashRelayIntent(baseParams, relayInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfCallsArrayInDestinationCallIsEmpty() public {
        baseParams.destinationCalls[0].calls = new Payload.Call[](0);
        vm.expectRevert(AnypayRelayParams.InvalidCallInDestination.selector);
        AnypayRelayParams.hashRelayIntent(baseParams, relayInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfRelayInfosIsEmpty() public {
        relayInfos = new AnypayRelayInfo[](0);
        vm.expectRevert(AnypayRelayParams.RelayInfosIsEmpty.selector);
        AnypayRelayParams.hashRelayIntent(baseParams, relayInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfAttestationAddressIsZero() public {
        attestationAddress = address(0);
        vm.expectRevert(AnypayRelayParams.AttestationAddressIsZero.selector);
        AnypayRelayParams.hashRelayIntent(baseParams, relayInfos, attestationAddress);
    }
} 