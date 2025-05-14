// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {AnypayLiFiDecoder} from "src/libraries/AnypayLiFiDecoder.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";

struct AcrossV3Data {
    address receiverAddress;
    address refundAddress;
    address receivingAssetId;
    uint256 outputAmount;
    uint64 outputAmountPercent;
    address exclusiveRelayer;
    uint32 quoteTimestamp;
    uint32 fillDeadline;
    uint32 exclusivityDeadline;
    bytes message;
}

// Helper contract to test internal functions of AnypayLiFiDecoder library
contract DecoderTestHelper {
    function mockTryDecodeBridgeAndSwapData(bytes memory data)
        external
        view
        returns (ILiFi.BridgeData memory bridgeDataOut, LibSwap.SwapData[] memory swapDataOut)
    {
        return AnypayLiFiDecoder.tryDecodeBridgeAndSwapData(data);
    }

    // Needed for abi.encodeCall to have a target for mock function signatures
    function mockStartBridge(ILiFi.BridgeData memory, /*_bridgeData*/ AcrossV3Data calldata /*_acrossData*/ )
        external
        pure
    {}

    function mockSingleBridgeArg(ILiFi.BridgeData memory /*_bridgeData*/ ) external pure {}

    function mockSwapAndStartBridge(
        ILiFi.BridgeData memory, /*_bridgeData*/
        LibSwap.SwapData[] calldata, /*_swapData*/
        AcrossV3Data calldata /*_acrossData*/
    ) external pure {}
}

contract AnypayLiFiDecoderTest is Test {
    DecoderTestHelper public helper;
    address public user = makeAddr("user");
    address public originalReceiver = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF); // Sentinel

    ILiFi.BridgeData internal baseBridgeData;
    AcrossV3Data internal baseAcrossData;
    LibSwap.SwapData[] internal singleSwapData;

    bytes4 internal mockStartBridgeSelector = DecoderTestHelper.mockStartBridge.selector;
    bytes4 internal mockSwapAndStartBridgeSelector = DecoderTestHelper.mockSwapAndStartBridge.selector;
    bytes4 internal mockSingleBridgeArgSelector = DecoderTestHelper.mockSingleBridgeArg.selector;

    function setUp() public {
        helper = new DecoderTestHelper();

        baseBridgeData = ILiFi.BridgeData({
            transactionId: bytes32(uint256(1)),
            bridge: "across",
            integrator: "testDecode",
            referrer: address(0),
            sendingAssetId: address(0x111111111117dC0aa78b770fA6A738034120C302),
            receiver: originalReceiver,
            minAmount: 1 ether,
            destinationChainId: 10,
            hasSourceSwaps: false,
            hasDestinationCall: false
        });

        baseAcrossData = AcrossV3Data({
            receiverAddress: originalReceiver,
            refundAddress: user,
            receivingAssetId: address(0x022222222227dc0AA78b770fa6a738034120C302),
            outputAmount: 0.99 ether,
            outputAmountPercent: 0.99e18,
            exclusiveRelayer: address(0),
            quoteTimestamp: uint32(block.timestamp),
            fillDeadline: uint32(block.timestamp + 1 hours),
            exclusivityDeadline: uint32(block.timestamp + 30 minutes),
            message: ""
        });

        singleSwapData = new LibSwap.SwapData[](1);
        singleSwapData[0] = LibSwap.SwapData({
            callTo: address(0xdead),
            approveTo: address(0xdead),
            sendingAssetId: baseBridgeData.sendingAssetId,
            receivingAssetId: address(0xbeef),
            fromAmount: baseBridgeData.minAmount,
            callData: hex"",
            requiresDeposit: false
        });
    }

    function test_TryDecode_FullSuccess_BridgeAndSwaps() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x7D01));
        localBridgeData.hasSourceSwaps = true;

        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, singleSwapData, baseAcrossData));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.mockTryDecodeBridgeAndSwapData(encodedCall);

        assertEq(
            decodedBridgeData.transactionId, localBridgeData.transactionId, "TD01: BridgeData transactionId mismatch"
        );
        assertEq(decodedBridgeData.bridge, localBridgeData.bridge, "TD01: BridgeData bridge mismatch");
        assertEq(decodedSwapData.length, singleSwapData.length, "TD01: SwapData length mismatch");
        assertEq(decodedSwapData[0].callTo, singleSwapData[0].callTo, "TD01: SwapData[0].callTo mismatch");
    }

    function test_TryDecode_Success_BridgeAndEmptySwapsInTuple() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x7D02));
        LibSwap.SwapData[] memory emptySwapDataArray = new LibSwap.SwapData[](0);

        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, emptySwapDataArray, baseAcrossData));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.mockTryDecodeBridgeAndSwapData(encodedCall);

        assertEq(
            decodedBridgeData.transactionId, localBridgeData.transactionId, "TD02: BridgeData transactionId mismatch"
        );
        assertEq(decodedSwapData.length, 0, "TD02: Expected empty SwapData array");
    }

    function test_TryDecode_Reverts_TupleWithMismatchedSecondType() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x7D03));

        // Calldata for (ILiFi.BridgeData, AcrossV3Data)
        bytes memory encodedCall = abi.encodeCall(helper.mockStartBridge, (localBridgeData, baseAcrossData));

        // Expects revert because tryDecodeBridgeAndSwapData will attempt to decode as
        // (ILiFi.BridgeData, LibSwap.SwapData[]), which fails due to type mismatch.
        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", uint256(0x41)));
        helper.mockTryDecodeBridgeAndSwapData(encodedCall);
    }

    function test_TryDecode_Reverts_BridgeOnly_CalldataHasOnlyBridgeData() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x7D06)); // New transaction ID for this test

        // Encode calldata for a function that *only* takes ILiFi.BridgeData
        bytes memory encodedCall = abi.encodeCall(helper.mockSingleBridgeArg, (localBridgeData));

        // Expects revert because the calldata is too short for a tuple with two dynamic params.
        vm.expectRevert();
        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.mockTryDecodeBridgeAndSwapData(encodedCall);
    }

    function test_TryDecode_Fail_CalldataTooShortForBridge_ReturnsDefaults() public {
        bytes memory shortCalldata = hex"01020304"; // selector + 0 bytes for offset = 4 bytes total

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.mockTryDecodeBridgeAndSwapData(shortCalldata);

        // Assert default/empty BridgeData
        assertEq(decodedBridgeData.transactionId, bytes32(0), "TD04: Expected default transactionId");
        assertEq(decodedBridgeData.bridge, "", "TD04: Expected default bridge name");
        assertEq(decodedBridgeData.receiver, address(0), "TD04: Expected default receiver");

        // Assert empty SwapData
        assertEq(decodedSwapData.length, 0, "TD04: Expected empty SwapData array");
    }
}
