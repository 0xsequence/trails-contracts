// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {AnypayIntentParams} from "src/libraries/AnypayIntentParams.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

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
            behaviorOnError: 0 // RevertOnError
        });

        baseParams.userAddress = address(0x1234567890123456789012345678901234567890);

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
        
        params.originTokens = new AnypayIntentParams.OriginToken[](1);
        params.originTokens[0] = AnypayIntentParams.OriginToken({
            tokenAddress: 0x4444444444444444444444444444444444444444,
            chainId: 1
        });

        params.destinationCalls = new Payload.Decoded[](1);
        Payload.Call[] memory callsForPayload0 = new Payload.Call[](1);
        callsForPayload0[0] = Payload.Call({
            to: 0x1111111111111111111111111111111111111111,
            value: 123,
            data: bytes("data1"),
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: 0 // RevertOnError
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

        bytes32 expectedHash = 0x0b8d4dd3cd166737a495e2404a5f4b4f81b5643daa93687ef1678ba4ffefe528;
 
        bytes32 actualHash = AnypayIntentParams.hashIntentParams(params);
        assertEq(actualHash, expectedHash, "SingleValidCallPayload hash mismatch");
    }

    function testHashIntentParams_MultipleValidCallPayloads() public {
        AnypayIntentParams.IntentParamsData memory params;
        params.userAddress = 0x3333333333333333333333333333333333333333;

        params.originTokens = new AnypayIntentParams.OriginToken[](1);
        params.originTokens[0] = AnypayIntentParams.OriginToken({
            tokenAddress: 0x4444444444444444444444444444444444444444,
            chainId: 1
        });

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
            behaviorOnError: 0 // RevertOnError
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

        // Payload 1
        Payload.Call[] memory callsForPayload1_multi = new Payload.Call[](1);
        callsForPayload1_multi[0] = Payload.Call({
            to: 0x5555555555555555555555555555555555555555,
            value: 456,
            data: bytes("data2"),
            gasLimit: 0,
            delegateCall: false, // Changed from true in original Go test, as KIND_TRANSACTIONS implies no delegate
            onlyFallback: false,
            behaviorOnError: 1 // IgnoreError
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

        bytes32 expectedHash = 0xa6fa28fd6bb9ca5cae503c6bb67342d15b16749c32aafdc325323c37d50822ec;

        bytes32 actualHash = AnypayIntentParams.hashIntentParams(params);
        assertEq(actualHash, expectedHash, "MultipleValidCallPayloads hash mismatch");
    }
} 