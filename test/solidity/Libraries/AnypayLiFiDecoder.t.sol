// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {AnypayLiFiDecoder} from "src/libraries/AnypayLiFiDecoder.sol";
import {ILiFi} from "lifi-contracts/interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";

// Copied from AcrossFacetV3Wrapper.t.sol for calldata generation
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
    function testDecodeOnlyBridgeData(bytes memory data) external pure returns (ILiFi.BridgeData memory bd) {
        return AnypayLiFiDecoder.decodeOnlyBridgeData(data);
    }

    function testEmitDecodedBridgeData(bytes memory data) external {
        AnypayLiFiDecoder.emitDecodedBridgeData(data);
    }

    function testDecodeSwapDataTuple(bytes memory data) external view returns (LibSwap.SwapData[] memory swapDataOut) {
        return AnypayLiFiDecoder.decodeSwapDataTuple(data);
    }

    // Needed for abi.encodeCall to have a target for mock function signatures
    function mockStartBridge(ILiFi.BridgeData memory /*_bridgeData*/, AcrossV3Data calldata /*_acrossData*/) external pure {}

    function mockSwapAndStartBridge(
        ILiFi.BridgeData memory /*_bridgeData*/,
        LibSwap.SwapData[] calldata /*_swapData*/,
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

    // --- Selectors for mock functions ---
    bytes4 internal mockStartBridgeSelector = DecoderTestHelper.mockStartBridge.selector;
    bytes4 internal mockSwapAndStartBridgeSelector = DecoderTestHelper.mockSwapAndStartBridge.selector;


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
            outputAmountPercent: 0.99e18, // Assuming 18 decimals for percent
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

    // --- Tests for decodeOnlyBridgeData ---

    function test_DecodeOnlyBridgeData_Success() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0xBD01));

        bytes memory encodedCall = abi.encodeCall(helper.mockStartBridge, (localBridgeData, baseAcrossData));

        ILiFi.BridgeData memory decoded = helper.testDecodeOnlyBridgeData(encodedCall);

        assertEq(decoded.transactionId, localBridgeData.transactionId, "transactionId mismatch");
        assertEq(decoded.bridge, localBridgeData.bridge, "bridge mismatch");
        assertEq(decoded.integrator, localBridgeData.integrator, "integrator mismatch");
        assertEq(decoded.receiver, localBridgeData.receiver, "receiver mismatch");
        assertEq(decoded.destinationChainId, localBridgeData.destinationChainId, "destinationChainId mismatch");
    }

    function test_Revert_DecodeOnlyBridgeData_CalldataTooShort() public {
        bytes memory shortCalldata = hex"01020304"; // selector + insufficient data

        vm.expectRevert(AnypayLiFiDecoder.InvalidCalldataLengthForBridgeData.selector);
        helper.testDecodeOnlyBridgeData(shortCalldata);
    }

    // --- Tests for emitDecodedBridgeData ---

    function test_EmitDecodedBridgeData_Success() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0xBD02));
        localBridgeData.receiver = user;
        localBridgeData.destinationChainId = 42161;

        bytes memory encodedCall = abi.encodeCall(helper.mockStartBridge, (localBridgeData, baseAcrossData));

        vm.expectEmit(true, true, true, true, address(helper));
        emit AnypayLiFiDecoder.DecodedBridgeData(
            localBridgeData.transactionId,
            localBridgeData.receiver,
            localBridgeData.destinationChainId
        );
        helper.testEmitDecodedBridgeData(encodedCall);
    }

    // --- Tests for decodeSwapDataTuple ---

    function test_DecodeSwapDataTuple_WithSwaps_Success() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x5D01));
        localBridgeData.hasSourceSwaps = true;

        bytes memory encodedCall = abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, singleSwapData, baseAcrossData));

        LibSwap.SwapData[] memory decodedSwaps = helper.testDecodeSwapDataTuple(encodedCall);

        assertEq(decodedSwaps.length, singleSwapData.length, "swapData length mismatch");
        assertEq(decodedSwaps[0].callTo, singleSwapData[0].callTo, "swapData[0].callTo mismatch");
        assertEq(decodedSwaps[0].sendingAssetId, singleSwapData[0].sendingAssetId, "swapData[0].sendingAssetId mismatch");
        assertEq(decodedSwaps[0].receivingAssetId, singleSwapData[0].receivingAssetId, "swapData[0].receivingAssetId mismatch");
        assertEq(decodedSwaps[0].fromAmount, singleSwapData[0].fromAmount, "swapData[0].fromAmount mismatch");
    }

    function test_DecodeSwapDataTuple_NoSwaps_InCalldataStructure_ReturnsEmpty() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x5D02));
        LibSwap.SwapData[] memory emptySwapData = new LibSwap.SwapData[](0);

        bytes memory encodedCall = abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, emptySwapData, baseAcrossData));

        LibSwap.SwapData[] memory decodedSwaps = helper.testDecodeSwapDataTuple(encodedCall);
        assertEq(decodedSwaps.length, 0, "Expected empty array for no swaps in tuple");
    }
    
    function test_Revert_DecodeSwapDataTuple_CalldataForBridgeDataOnly() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x5D03));
        bytes memory encodedCall = abi.encodeCall(helper.mockStartBridge, (localBridgeData, baseAcrossData));
        
        vm.expectRevert();
        helper.testDecodeSwapDataTuple(encodedCall);
    }


    function test_DecodeSwapDataTuple_CalldataTooShortForTuple_ReturnsEmpty() public {
        bytes memory shortCalldata = new bytes(67);
        shortCalldata[0] = 0x01; shortCalldata[1] = 0x02; shortCalldata[2] = 0x03; shortCalldata[3] = 0x04;

        LibSwap.SwapData[] memory decodedSwaps = helper.testDecodeSwapDataTuple(shortCalldata);
        assertEq(decodedSwaps.length, 0, "Expected empty array for short calldata");
    }

    // --- Former emitDecodedSwapData tests, now testing decodeSwapDataTuple directly ---

    function test_FormerlyEmit_DecodeSwapDataTuple_WithSwaps_Success() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0xE5D01));
        localBridgeData.hasSourceSwaps = true;

        bytes memory encodedCall = abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, singleSwapData, baseAcrossData));
        
        LibSwap.SwapData[] memory decodedSwaps = helper.testDecodeSwapDataTuple(encodedCall);

        assertEq(decodedSwaps.length, singleSwapData.length, "ESD01: swapData length mismatch");
        assertEq(decodedSwaps[0].callTo, singleSwapData[0].callTo, "ESD01: swapData[0].callTo mismatch");
        assertEq(decodedSwaps[0].sendingAssetId, singleSwapData[0].sendingAssetId, "ESD01: swapData[0].sendingAssetId mismatch");
    }

    function test_FormerlyEmit_DecodeSwapDataTuple_NoSwapsInTuple_ReturnsEmpty() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0xE5D02));
        LibSwap.SwapData[] memory emptySwapData = new LibSwap.SwapData[](0);

        bytes memory encodedCall = abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, emptySwapData, baseAcrossData));
        
        LibSwap.SwapData[] memory decodedSwaps = helper.testDecodeSwapDataTuple(encodedCall);
        assertEq(decodedSwaps.length, 0, "ESD02: Expected empty array for no swaps in tuple");
    }

    function test_FormerlyEmit_Revert_DecodeSwapDataTuple_CalldataForBridgeDataOnly() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0xE5D03));
        bytes memory encodedCall = abi.encodeCall(helper.mockStartBridge, (localBridgeData, baseAcrossData));

        vm.expectRevert(); 
        helper.testDecodeSwapDataTuple(encodedCall);
    }

    function test_FormerlyEmit_DecodeSwapDataTuple_CalldataTooShortForTuple_ReturnsEmpty() public {
        bytes memory shortCalldata = new bytes(67); 
        shortCalldata[0] = 0xde; shortCalldata[1] = 0xad; shortCalldata[2] = 0xbe; shortCalldata[3] = 0xef;

        LibSwap.SwapData[] memory decodedSwaps = helper.testDecodeSwapDataTuple(shortCalldata);
        assertEq(decodedSwaps.length, 0, "ESD04: Expected empty array for short calldata");
    }
} 