// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {AnypayLifiParams} from "@/libraries/AnypayLifiParams.sol";
import {AnypayLiFiInfo} from "@/libraries/AnypayLiFiInterpreter.sol";

contract AnypayLifiParamsTest is Test {
    AnypayLifiParams.IntentParamsData internal baseParams;
    AnypayLiFiInfo[] internal lifiInfos;
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

        baseParams.originTokens = new AnypayLifiParams.OriginToken[](1);
        baseParams.originTokens[0] = AnypayLifiParams.OriginToken({
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

        baseParams.destinationTokens = new AnypayLifiParams.DestinationToken[](1);
        baseParams.destinationTokens[0] = AnypayLifiParams.DestinationToken({
            tokenAddress: address(0x00000000000000000000000000000000000000C1),
            chainId: 1,
            amount: 2 ether
        });

        lifiInfos = new AnypayLiFiInfo[](1);
        lifiInfos[0] = AnypayLiFiInfo({
            originToken: 0x1111111111111111111111111111111111111111,
            amount: 100,
            originChainId: 1,
            destinationChainId: 10
        });

        attestationAddress = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;
    }

    function testHashLifiIntent_HappyPath() public {
        vm.chainId(1);
        bytes32 hash = AnypayLifiParams.hashLifiIntent(baseParams, lifiInfos, attestationAddress);
        // This is a snapshot of the expected hash. If the hashing logic changes, this value needs to be updated.
        bytes32 expectedHash = 0x0cd0ee49135999e83aeb39ec57f891eceffe651a057def1cd861751fa3eb7853;
        assertEq(hash, expectedHash, "LiFi intent hash mismatch");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfUserAddressIsZero() public {
        baseParams.userAddress = address(0);
        vm.expectRevert(AnypayLifiParams.UserAddressIsZero.selector);
        AnypayLifiParams.hashLifiIntent(baseParams, lifiInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfOriginTokensIsEmpty() public {
        baseParams.originTokens = new AnypayLifiParams.OriginToken[](0);
        vm.expectRevert(AnypayLifiParams.OriginTokensIsEmpty.selector);
        AnypayLifiParams.hashLifiIntent(baseParams, lifiInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfDestinationCallsIsEmpty() public {
        baseParams.destinationCalls = new Payload.Decoded[](0);
        vm.expectRevert(AnypayLifiParams.DestinationCallsIsEmpty.selector);
        AnypayLifiParams.hashLifiIntent(baseParams, lifiInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfDestinationTokensIsEmpty() public {
        baseParams.destinationTokens = new AnypayLifiParams.DestinationToken[](0);
        vm.expectRevert(AnypayLifiParams.DestinationTokensIsEmpty.selector);
        AnypayLifiParams.hashLifiIntent(baseParams, lifiInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfDestinationCallKindIsNotTransactions() public {
        baseParams.destinationCalls[0].kind = Payload.KIND_MESSAGE;
        vm.expectRevert(AnypayLifiParams.InvalidDestinationCallKind.selector);
        AnypayLifiParams.hashLifiIntent(baseParams, lifiInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfCallsArrayInDestinationCallIsEmpty() public {
        baseParams.destinationCalls[0].calls = new Payload.Call[](0);
        vm.expectRevert(AnypayLifiParams.InvalidCallInDestination.selector);
        AnypayLifiParams.hashLifiIntent(baseParams, lifiInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfLifiInfosIsEmpty() public {
        lifiInfos = new AnypayLiFiInfo[](0);
        vm.expectRevert(AnypayLifiParams.LifiInfosIsEmpty.selector);
        AnypayLifiParams.hashLifiIntent(baseParams, lifiInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfAttestationAddressIsZero() public {
        attestationAddress = address(0);
        vm.expectRevert(AnypayLifiParams.AttestationAddressIsZero.selector);
        AnypayLifiParams.hashLifiIntent(baseParams, lifiInfos, attestationAddress);
    }
} 