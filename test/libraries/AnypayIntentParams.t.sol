// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {AnypayIntentParams} from "src/libraries/AnypayIntentParams.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {AnypayLifiInfo} from "src/libraries/AnypayLiFiInterpreter.sol";

contract AnypayIntentParamsTest is Test {
    AnypayIntentParams.IntentParamsData internal baseParams;
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

        baseParams.originTokens = new AnypayIntentParams.OriginToken[](1);
        baseParams.originTokens[0] = AnypayIntentParams.OriginToken({
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

        baseParams.destinationTokens = new AnypayIntentParams.DestinationToken[](1);
        baseParams.destinationTokens[0] = AnypayIntentParams.DestinationToken({
            tokenAddress: address(0x00000000000000000000000000000000000000C1),
            chainId: 1,
            amount: 2 ether
        });
    }

    // function testRevertIfUserAddressIsZero() public {
    //     AnypayIntentParams.IntentParamsData memory params = baseParams;
    //     params.userAddress = address(0);
    //     vm.expectRevert(AnypayIntentParams.UserAddressIsZero.selector);
    //     AnypayIntentParams.hashIntentParams(params);
    // }

    // function testRevertIfOriginTokensIsEmpty() public {
    //     AnypayIntentParams.IntentParamsData memory params = baseParams;
    //     params.originTokens = new AnypayIntentParams.OriginToken[](0);
    //     vm.expectRevert(AnypayIntentParams.OriginTokensIsEmpty.selector);
    //     AnypayIntentParams.hashIntentParams(params);
    // }

    // function testRevertIfDestinationCallsIsEmpty() public {
    //     AnypayIntentParams.IntentParamsData memory params = baseParams;
    //     params.destinationCalls = new Payload.Decoded[](0);
    //     vm.expectRevert(AnypayIntentParams.DestinationCallsIsEmpty.selector);
    //     AnypayIntentParams.hashIntentParams(params);
    // }

    // function testRevertIfDestinationTokensIsEmpty() public {
    //     AnypayIntentParams.IntentParamsData memory params = baseParams;
    //     params.destinationTokens = new AnypayIntentParams.DestinationToken[](0);
    //     vm.expectRevert(AnypayIntentParams.DestinationTokensIsEmpty.selector);
    //     AnypayIntentParams.hashIntentParams(params);
    // }

    // function testRevertIfDestinationCallKindIsNotTransactions() public {
    //     AnypayIntentParams.IntentParamsData memory params = baseParams;
    //     // Modify the first destination call to have a non-KIND_TRANSACTIONS kind
    //     params.destinationCalls[0].kind = Payload.KIND_MESSAGE; // Or any other kind
    //     vm.expectRevert(AnypayIntentParams.InvalidDestinationCallKind.selector);
    //     AnypayIntentParams.hashIntentParams(params);
    // }

    // function testRevertIfCallsArrayInDestinationCallIsEmpty() public {
    //     AnypayIntentParams.IntentParamsData memory params = baseParams;
    //     // Modify the first destination call to have an empty calls array
    //     params.destinationCalls[0].calls = new Payload.Call[](0);
    //     vm.expectRevert(AnypayIntentParams.InvalidCallInDestination.selector);
    //     AnypayIntentParams.hashIntentParams(params);
    // }

    function testHashIntentParams_SingleValidCallPayload() public {
        AnypayIntentParams.IntentParamsData memory params;
        params.userAddress = 0x3333333333333333333333333333333333333333;
        params.nonce = 0;

        params.originTokens = new AnypayIntentParams.OriginToken[](1);
        params.originTokens[0] =
            AnypayIntentParams.OriginToken({tokenAddress: 0x4444444444444444444444444444444444444444, chainId: 1});

        params.destinationCalls = new Payload.Decoded[](1);
        Payload.Call[] memory callsForPayload0 = new Payload.Call[](1);
        callsForPayload0[0] = Payload.Call({
            to: 0x1111111111111111111111111111111111111111,
            value: 123,
            data: bytes("data1"),
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: 0
        });

        params.destinationCalls[0] = Payload.Decoded({
            kind: Payload.KIND_TRANSACTIONS,
            noChainId: false,
            calls: callsForPayload0,
            space: 0,
            nonce: 0,
            message: "",
            imageHash: bytes32(0),
            digest: bytes32(0),
            parentWallets: new address[](0)
        });

        params.destinationTokens = new AnypayIntentParams.DestinationToken[](1);
        params.destinationTokens[0] = AnypayIntentParams.DestinationToken({
            tokenAddress: 0x4444444444444444444444444444444444444444,
            chainId: 1,
            amount: 123
        });

        bytes32 expectedHash = 0x4479e1ed63b1cf70ed13228bec79f2a1d2ffa0e9372e2afc7d82263cd8107451;

        vm.chainId(1);
        bytes32 actualHash = AnypayIntentParams.hashIntentParams(params);
        assertEq(actualHash, expectedHash, "SingleValidCallPayload hash mismatch");
    }

    function testHashIntentParams_MultipleValidCallPayloads() public {
        AnypayIntentParams.IntentParamsData memory params;
        params.userAddress = 0x3333333333333333333333333333333333333333;
        params.nonce = 0;

        params.originTokens = new AnypayIntentParams.OriginToken[](1);
        params.originTokens[0] =
            AnypayIntentParams.OriginToken({tokenAddress: 0x4444444444444444444444444444444444444444, chainId: 1});

        params.destinationCalls = new Payload.Decoded[](2);
        // Payload 0
        Payload.Call[] memory callsForPayload0_multi = new Payload.Call[](1);
        callsForPayload0_multi[0] = Payload.Call({
            to: 0x1111111111111111111111111111111111111111,
            value: 123,
            data: bytes("data1"),
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: 0
        });
        params.destinationCalls[0] = Payload.Decoded({
            kind: Payload.KIND_TRANSACTIONS,
            noChainId: false,
            calls: callsForPayload0_multi,
            space: 0,
            nonce: 0,
            message: "",
            imageHash: bytes32(0),
            digest: bytes32(0),
            parentWallets: new address[](0)
        });

        Payload.Call[] memory callsForPayload1_multi = new Payload.Call[](1);
        callsForPayload1_multi[0] = Payload.Call({
            to: 0x5555555555555555555555555555555555555555,
            value: 456,
            data: bytes("data2"),
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: 0
        });
        params.destinationCalls[1] = Payload.Decoded({
            kind: Payload.KIND_TRANSACTIONS,
            noChainId: false,
            calls: callsForPayload1_multi,
            space: 0,
            nonce: 0,
            message: "",
            imageHash: bytes32(0),
            digest: bytes32(0),
            parentWallets: new address[](0)
        });

        params.destinationTokens = new AnypayIntentParams.DestinationToken[](1);
        params.destinationTokens[0] = AnypayIntentParams.DestinationToken({
            tokenAddress: 0x4444444444444444444444444444444444444444,
            chainId: 1,
            amount: 123
        });

        bytes32 expectedHash = 0x64631a48bc218cd8196dca22437223d90dc9caa8208284cdcea4b7f32bfc7cec;

        vm.chainId(1);
        bytes32 actualHash = AnypayIntentParams.hashIntentParams(params);
        assertEq(actualHash, expectedHash, "MultipleValidCallPayloads hash mismatch");
    }

    function testGetAnypayLifiInfoHash_SingleInfo() public {
        AnypayLifiInfo[] memory lifiInfos = new AnypayLifiInfo[](1);
        lifiInfos[0] = AnypayLifiInfo({
            originToken: 0x1111111111111111111111111111111111111111,
            minAmount: 100,
            originChainId: 1,
            destinationChainId: 10
        });
        address attestationAddress = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;

        bytes32 expectedHash = 0x21872bd6b64711c4a5aecba95829c612f0b50c63f1a26991c2f76cf4a754aede;
        bytes32 actualHash = AnypayIntentParams.getAnypayLifiInfoHash(lifiInfos, attestationAddress);
        assertEq(actualHash, expectedHash, "SingleInfo hash mismatch");
    }

    function testGetAnypayLifiInfoHash_MultipleInfo() public {
        AnypayLifiInfo[] memory lifiInfos = new AnypayLifiInfo[](2);
        lifiInfos[0] = AnypayLifiInfo({
            originToken: 0x1111111111111111111111111111111111111111,
            minAmount: 100,
            originChainId: 1,
            destinationChainId: 10
        });
        lifiInfos[1] = AnypayLifiInfo({
            originToken: 0x2222222222222222222222222222222222222222,
            minAmount: 200,
            originChainId: 137,
            destinationChainId: 42161
        });
        address attestationAddress = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;

        bytes32 expectedHash = 0xd18e54455db64ba31b9f9a447e181f83977cb70b136228d64ac85d64a6aefe71;
        bytes32 actualHash = AnypayIntentParams.getAnypayLifiInfoHash(lifiInfos, attestationAddress);
        assertEq(actualHash, expectedHash, "MultipleInfo hash mismatch");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testGetAnypayLifiInfoHash_EmptyInfo_ShouldRevert() public {
        AnypayLifiInfo[] memory lifiInfos = new AnypayLifiInfo[](0);
        address attestationAddress = 0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC;

        vm.expectRevert(AnypayIntentParams.LifiInfosIsEmpty.selector);
        AnypayIntentParams.getAnypayLifiInfoHash(lifiInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testGetAnypayLifiInfoHash_AttestationAddressIsZero_ShouldRevert() public {
        AnypayLifiInfo[] memory lifiInfos = new AnypayLifiInfo[](1);
        lifiInfos[0] = AnypayLifiInfo({
            originToken: 0x1111111111111111111111111111111111111111,
            minAmount: 100,
            originChainId: 1,
            destinationChainId: 10
        });
        address attestationAddress = address(0);

        vm.expectRevert(AnypayIntentParams.AttestationAddressIsZero.selector);
        AnypayIntentParams.getAnypayLifiInfoHash(lifiInfos, attestationAddress);
    }
}
