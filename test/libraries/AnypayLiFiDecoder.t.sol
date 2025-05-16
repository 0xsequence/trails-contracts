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

    function mockDecodeLifiSwapDataPayloadAsArray(bytes memory data)
        public
        pure
        returns (LibSwap.SwapData[] memory swapDataArrayOut)
    {
        return AnypayLiFiDecoder.decodeLifiSwapDataPayloadAsArray(data);
    }

    function mockDecodeLifiSwapDataPayloadAsSingle(bytes memory data)
        public
        pure
        returns (LibSwap.SwapData memory singleSwapDataOut)
    {
        return AnypayLiFiDecoder.decodeLifiSwapDataPayloadAsSingle(data);
    }

    function mockDecodeLiFiDataOrRevert(bytes memory data)
        public
        pure
        returns (ILiFi.BridgeData memory finalBridgeData, LibSwap.SwapData[] memory finalSwapDataArray)
    {
        return AnypayLiFiDecoder.decodeLiFiDataOrRevert(data);
    }

    function mockSwapTokensSingle(
        bytes32, // _transactionId
        string calldata, // _integrator
        string calldata, // _referrer
        address, // _receiver
        uint256, // _minAmountOut
        LibSwap.SwapData calldata // _swapData
    ) external pure {}

    function mockSwapTokensMultiple(
        bytes32, // _transactionId
        string calldata, // _integrator
        string calldata, // _referrer
        address, // _receiver
        uint256, // _minAmountOut
        LibSwap.SwapData[] calldata // _swapData
    ) external pure {}

    // Mock function for GenericSwapFacet (older version) - assuming it might be needed by other tests if user undid removal.
    // If not, this can be removed if no other test uses mockSwapTokensGeneric_GSF_Selector.
    function mockSwapTokensGeneric_GSF(
        bytes32, // _transactionId
        string calldata, // _integrator
        string calldata, // _referrer
        address payable, // _receiver
        uint256, // _minAmount
        LibSwap.SwapData[] calldata // _swapData
    ) external pure {}

    function mockCompletelyUnrelated(uint256 valA, bool flagB) external pure {}
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
    bytes4 internal mockSwapTokensSingleSelector = DecoderTestHelper.mockSwapTokensSingle.selector;
    bytes4 internal mockSwapTokensMultipleSelector = DecoderTestHelper.mockSwapTokensMultiple.selector;
    bytes4 internal mockCompletelyUnrelatedSelector = DecoderTestHelper.mockCompletelyUnrelated.selector;

    // Dummy prefix data for GenericSwapFacetV3 style calldata
    bytes32 internal dummyTxId = bytes32(uint256(0xABC));
    string internal dummyIntegrator = "TestIntegrator";
    string internal dummyReferrer = "TestReferrer";
    address internal dummyReceiver = makeAddr("dummyReceiver");
    uint256 internal dummyMinAmountOut = 1 wei;

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

    function test_DecodeLifiSwapDataPayloadAsArray_Success() public {
        LibSwap.SwapData[] memory expectedSwapData = singleSwapData; // Re-use existing singleSwapData for simplicity
        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensMultiple,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, expectedSwapData)
        );

        LibSwap.SwapData[] memory decodedSwapData = helper.mockDecodeLifiSwapDataPayloadAsArray(encodedCall);

        assertEq(decodedSwapData.length, expectedSwapData.length, "DPA01: SwapData array length mismatch");
        assertEq(decodedSwapData[0].callTo, expectedSwapData[0].callTo, "DPA01: SwapData[0].callTo mismatch");
    }

    function test_DecodeLifiSwapDataPayloadAsArray_Reverts_AbiDecodeError() public {
        // Construct calldata that is long enough but malformed for abi.decode
        // (bytes32, string, string, address, uint256, LibSwap.SwapData[])
        // We'll replace the SwapData[] part with something that's not an array (e.g., a single struct)
        bytes memory malformedPayload = abi.encode(
            dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, singleSwapData[0] // single struct instead of array
        );
        bytes memory encodedCall = abi.encodePacked(mockSwapTokensMultipleSelector, malformedPayload);

        vm.expectRevert(); // Expects a generic abi.decode error (panic or otherwise)
        helper.mockDecodeLifiSwapDataPayloadAsArray(encodedCall);
    }

    // Test cases for decodeLifiSwapDataPayloadAsSingle
    function test_DecodeLifiSwapDataPayloadAsSingle_Success() public {
        LibSwap.SwapData memory expectedSwapData = singleSwapData[0];
        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensSingle,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, expectedSwapData)
        );

        LibSwap.SwapData memory decodedSwapData = helper.mockDecodeLifiSwapDataPayloadAsSingle(encodedCall);

        assertEq(decodedSwapData.callTo, expectedSwapData.callTo, "DPS01: SwapData.callTo mismatch");
        assertEq(decodedSwapData.sendingAssetId, expectedSwapData.sendingAssetId, "DPS01: SwapData.sendingAssetId mismatch");
    }
    
    function test_DecodeLifiSwapDataPayloadAsSingle_Reverts_AbiDecodeError() public {
        // Construct calldata that is long enough but malformed for abi.decode
        // (bytes32, string, string, address, uint256, LibSwap.SwapData)
        // We'll replace the SwapData part with an array
        bytes memory malformedPayload = abi.encode(
            dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, singleSwapData // array instead of single struct
        );
        bytes memory encodedCall = abi.encodePacked(mockSwapTokensSingleSelector, malformedPayload);

        vm.expectRevert(); // Expects a generic abi.decode error
        helper.mockDecodeLifiSwapDataPayloadAsSingle(encodedCall);
    }

    function test_DecodeOrRevert_Reverts_CalldataTooShort_WithMinimalCalldata() public {
        // With very short calldata (e.g., just a 4-byte selector like hex"deadbeef"):
        // 1. tryDecodeBridgeAndSwapData: data.length (4) < minLenForBridgeDataOffset (36). Returns defaults.
        // 2. decodeLifiSwapDataPayloadAsArray: data.length (4) < minCalldataLenForPrefixAndOneOffset (196). Reverts CalldataTooShortForPayload.
        bytes memory minimalCalldata = hex"deadbeef"; // 4 bytes, could be any unrecognised selector
        vm.expectRevert(AnypayLiFiDecoder.CalldataTooShortForPayload.selector);
        helper.mockDecodeLiFiDataOrRevert(minimalCalldata);
    }

    function test_DecodeOrRevert_Reverts_TryDecode_AbiError() public {
        // Use calldata from test_TryDecode_Reverts_TupleWithMismatchedSecondType
        // which causes abi.decode panic 0x41 in tryDecodeBridgeAndSwapData
        bytes memory encodedCall = abi.encodeCall(helper.mockStartBridge, (baseBridgeData, baseAcrossData));

        vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", uint256(0x41)));
        helper.mockDecodeLiFiDataOrRevert(encodedCall);
    }
    
    function test_DecodeOrRevert_Reverts_PayloadAsArray_CalldataTooShort() public {
        // Calldata that passes tryDecode (returns empty swaps) but is too short for PayloadAsArray's prefix.
        // e.g. A call to mockSingleBridgeArg(baseBridgeData)
        bytes memory encodedCall = abi.encodeCall(helper.mockSingleBridgeArg, (baseBridgeData));
     
        bytes memory shortCalldata = hex"0102030405060708";
        vm.expectRevert(AnypayLiFiDecoder.CalldataTooShortForPayload.selector);
        helper.mockDecodeLiFiDataOrRevert(shortCalldata);
    }

    function test_DecodeOrRevert_Reverts_PayloadAsArray_AbiError() public {
        // Calldata that:
        // 1. Passes tryDecode (returns empty swaps). E.g. mockSingleBridgeArg(baseBridgeData).
        // 2. Is long enough for PayloadAsArray's prefix, but malformed for its abi.decode.
        //    mockSingleBridgeArg(baseBridgeData) calldata will be used.
        //    decodeLifiSwapDataPayloadAsArray will try to decode baseBridgeData as (prefix, SwapData[]), will cause abi.decode error.
        bytes memory encodedCall = abi.encodeCall(helper.mockSingleBridgeArg, (baseBridgeData));
        
        vm.expectRevert(); // General abi.decode error from second stage
        helper.mockDecodeLiFiDataOrRevert(encodedCall);
    }

    function test_DecodeOrRevert_Reverts_PayloadAsSingle_AbiError() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        LibSwap.SwapData[] memory emptySwapDataArray = new LibSwap.SwapData[](0);
        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, emptySwapDataArray, baseAcrossData));
        
        vm.expectRevert();
        helper.mockDecodeLiFiDataOrRevert(encodedCall);
    }

    function test_DecodeOrRevert_Reverts_WithUnrelatedCalldata_Short() public {
        // Calldata is just the selector of a completely unrelated function.
        bytes memory unrelatedSelectorOnly = abi.encodePacked(mockCompletelyUnrelatedSelector);

        // Expected path:
        // 1. tryDecodeBridgeAndSwapData(unrelatedSelectorOnly): length 4 < 36. Returns default, empty. No revert.
        // 2. decodeLifiSwapDataPayloadAsArray(unrelatedSelectorOnly): length 4 < 196. Reverts CalldataTooShortForPayload.
        vm.expectRevert(AnypayLiFiDecoder.CalldataTooShortForPayload.selector);
        helper.mockDecodeLiFiDataOrRevert(unrelatedSelectorOnly);
    }

    function test_DecodeOrRevert_Reverts_Panic_WithUnrelatedCalldata_Longer() public {
        // Calldata is for a completely unrelated function with some arguments.
        bytes memory unrelatedFullCall = abi.encodeCall(helper.mockCompletelyUnrelated, (123_456, true));
        // Length of this calldata is 4 (selector) + 32 (uint256) + 32 (bool) = 68 bytes.

        // Expected path:
        // 1. tryDecodeBridgeAndSwapData(unrelatedFullCall):
        //    data.length (68) >= minLenForTupleOffsets (68).
        //    Calls _getMemorySlice(data, 4).
        //    Attempts abi.decode(slice from unrelatedFullCall, (ILiFi.BridgeData, LibSwap.SwapData[])).
        //    The slice contains (uint256, bool). This will cause an abi.decode panic due to type mismatch.
        vm.expectRevert(); // Expect a generic ABI decode panic (e.g., Panic(0x32) or other decode errors)
        helper.mockDecodeLiFiDataOrRevert(unrelatedFullCall);
    }

    function test_DecodeOrRevert_Reverts_PayloadAsSingle_CalldataTooShort() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        LibSwap.SwapData[] memory emptySwapDataArray = new LibSwap.SwapData[](0);
        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, emptySwapDataArray, baseAcrossData));
        
        vm.expectRevert();
        helper.mockDecodeLiFiDataOrRevert(encodedCall);
    }

        // Test cases for decodeLiFiDataOrRevert
    function test_DecodeOrRevert_Strategy1_TryDecodeBridgeAndSwap_Success() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.hasSourceSwaps = true;
        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, singleSwapData, baseAcrossData));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.mockDecodeLiFiDataOrRevert(encodedCall);

        assertEq(decodedBridgeData.transactionId, localBridgeData.transactionId, "DOR01: BridgeData.transactionId mismatch");
        assertEq(decodedSwapData.length, singleSwapData.length, "DOR01: SwapData length mismatch");
        assertEq(decodedSwapData[0].callTo, singleSwapData[0].callTo, "DOR01: SwapData[0].callTo mismatch");
    }

    function test_DecodeOrRevert_Strategy2_PayloadAsArray_Success() public {
        // Calldata that fails tryDecodeBridgeAndSwapData (e.g., it's not (BridgeData, SwapData[]))
        // but succeeds for decodeLifiSwapDataPayloadAsArray
        LibSwap.SwapData[] memory expectedSwapData = singleSwapData;
        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensMultiple,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, expectedSwapData)
        );
        
        // To make it fail tryDecodeBridgeAndSwapData, ensure it's not decodable as (BridgeData, SwapData[])
        // or (BridgeData). We can make it look like a BridgeData by ensuring the first arg is a struct.
        // The mockSwapTokensMultiple already has a bytes32 as the first arg. This will likely fail
        // the BridgeData decoding (which has bytes32, string, string, address, address, uint256, uint64, bool, bool)

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.mockDecodeLiFiDataOrRevert(encodedCall);

        // BridgeData should be default as first strategy fails to populate it meaningfully for this input type
        assertEq(decodedBridgeData.transactionId, bytes32(0), "DOR02: BridgeData should be default");
        assertEq(decodedSwapData.length, expectedSwapData.length, "DOR02: SwapData array length mismatch");
        assertEq(decodedSwapData[0].callTo, expectedSwapData[0].callTo, "DOR02: SwapData[0].callTo mismatch");
    }

    function test_DecodeOrRevert_Strategy3_PayloadAsSingle_Success() public {
        LibSwap.SwapData memory expectedSwapData = singleSwapData[0];
        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensSingle,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, expectedSwapData)
        );

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.mockDecodeLiFiDataOrRevert(encodedCall);
        
        assertEq(decodedBridgeData.transactionId, bytes32(0), "DOR03: BridgeData should be default");
        assertEq(decodedSwapData.length, 1, "DOR03: SwapData array length should be 1");
        assertEq(decodedSwapData[0].callTo, expectedSwapData.callTo, "DOR03: SwapData[0].callTo mismatch");
    }
}

