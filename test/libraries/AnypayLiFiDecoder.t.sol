// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {AnypayLiFiDecoder, AnypayLiFiDecodingLogic} from "src/libraries/AnypayLiFiDecoder.sol";
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
    function decodeBridgeAndSwapData(bytes memory data)
        external
        view
        returns (ILiFi.BridgeData memory bridgeDataOut, LibSwap.SwapData[] memory swapDataOut)
    {
        return AnypayLiFiDecoder.decodeLiFiDataOrRevert(data);
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

    function decodeLiFiDataOrRevert(bytes memory data)
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

    function test_DecodeOrRevert_Success_BridgeAndSwaps() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x7D01));
        localBridgeData.hasSourceSwaps = true;

        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, singleSwapData, baseAcrossData));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall);

        assertEq(
            decodedBridgeData.transactionId, localBridgeData.transactionId, "TD01: BridgeData transactionId mismatch"
        );
        assertEq(decodedBridgeData.bridge, localBridgeData.bridge, "TD01: BridgeData bridge mismatch");
        assertEq(decodedSwapData.length, singleSwapData.length, "TD01: SwapData length mismatch");
        assertEq(decodedSwapData[0].callTo, singleSwapData[0].callTo, "TD01: SwapData[0].callTo mismatch");
    }

    function test_DecodeOrRevert_Success_BridgeAndEmptySwapsInTuple() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x7D02));
        LibSwap.SwapData[] memory emptySwapDataArray = new LibSwap.SwapData[](0);

        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, emptySwapDataArray, baseAcrossData));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall);

        assertEq(
            decodedBridgeData.transactionId, localBridgeData.transactionId, "TD02: BridgeData transactionId mismatch"
        );
        assertEq(decodedSwapData.length, 0, "TD02: Expected empty SwapData array");
    }

    function test_DecodeOrRevert_Success_ForBridgeData_WhenTupleSecondElementMismatched() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x7D03));

        // Calldata for (ILiFi.BridgeData, AcrossV3Data)
        bytes memory encodedCall = abi.encodeCall(helper.mockStartBridge, (localBridgeData, baseAcrossData));

        // tryDecodeBridgeAndSwapData should catch the internal revert and return success=false
        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall);

        assertEq(
            decodedBridgeData.transactionId, localBridgeData.transactionId, "TD03: BridgeData transactionId mismatch"
        );
        assertEq(decodedSwapData.length, 0, "TD03: SwapData should be empty when second tuple element is mismatched");
    }

    function test_DecodeOrRevert_Success_BridgeOnly_CalldataHasOnlyBridgeData() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x7D06)); // New transaction ID for this test

        // Encode calldata for a function that *only* takes ILiFi.BridgeData
        bytes memory encodedCall = abi.encodeCall(helper.mockSingleBridgeArg, (localBridgeData));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall);

        assertEq(
            decodedBridgeData.transactionId, localBridgeData.transactionId, "TD06: BridgeData transactionId mismatch"
        );
        assertEq(decodedSwapData.length, 0, "TD06: SwapData should be empty for bridge-only calldata");
    }

    function test_DecodeOrRevert_Reverts_CalldataTooShortForBridge_ReturnsDefaults() public {
        bytes memory shortCalldata = hex"01020304";

        vm.expectRevert(AnypayLiFiDecoder.NoLiFiDataDecoded.selector);
        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(shortCalldata);
    }

    function test_DecodeOrRevert_Success_SwapPayloadAsArray() public {
        LibSwap.SwapData[] memory expectedSwapData = singleSwapData; // Re-use existing singleSwapData for simplicity
        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensMultiple,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, expectedSwapData)
        );

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall);

        assertEq(decodedSwapData.length, expectedSwapData.length, "DPA01: SwapData array length mismatch");
        assertEq(decodedSwapData[0].callTo, expectedSwapData[0].callTo, "DPA01: SwapData[0].callTo mismatch");
    }

    // Test cases for decodeLifiSwapDataPayloadAsSingle
    function test_DecodeOrRevert_Success_SwapPayloadAsSingle() public {
        LibSwap.SwapData memory expectedSwapData = singleSwapData[0];
        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensSingle,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, expectedSwapData)
        );

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall);

        assertEq(decodedSwapData[0].callTo, expectedSwapData.callTo, "DPS01: SwapData.callTo mismatch");
        assertEq(
            decodedSwapData[0].sendingAssetId,
            expectedSwapData.sendingAssetId,
            "DPS01: SwapData.sendingAssetId mismatch"
        );
    }

    function test_DecodeOrRevert_Reverts_CalldataTooShort_WithMinimalCalldata() public {
        bytes memory minimalCalldata = hex"deadbeef";
        vm.expectRevert(AnypayLiFiDecoder.NoLiFiDataDecoded.selector);
        helper.decodeLiFiDataOrRevert(minimalCalldata);
    }

    function test_DecodeOrRevert_Reverts_TryDecode_AbiError() public {
        bytes memory encodedCall = abi.encodeCall(helper.mockStartBridge, (baseBridgeData, baseAcrossData));

        helper.decodeLiFiDataOrRevert(encodedCall);
    }

    function test_DecodeOrRevert_Reverts_PayloadAsArray_CalldataTooShort() public {
        bytes memory shortCalldata = hex"0102030405060708";

        vm.expectRevert(AnypayLiFiDecoder.NoLiFiDataDecoded.selector);
        helper.decodeLiFiDataOrRevert(shortCalldata);
    }

    function test_DecodeOrRevert_Reverts_WithUnrelatedCalldata_Short() public {
        bytes memory unrelatedSelectorOnly = abi.encodePacked(mockCompletelyUnrelatedSelector);

        vm.expectRevert(AnypayLiFiDecoder.NoLiFiDataDecoded.selector);
        helper.decodeLiFiDataOrRevert(unrelatedSelectorOnly);
    }

    function test_DecodeOrRevert_Reverts_Panic_WithUnrelatedCalldata_Longer() public {
        // Calldata is for a completely unrelated function with some arguments.
        bytes memory unrelatedFullCall = abi.encodeCall(helper.mockCompletelyUnrelated, (123_456, true));
        // Length of this calldata is 4 (selector) + 32 (uint256) + 32 (bool) = 68 bytes.

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(unrelatedFullCall);
    }

    function test_DecodeOrRevert_Reverts_PayloadAsSingle_CalldataTooShort() public {
        bytes memory veryShortCalldata = hex"12345678";

        vm.expectRevert(AnypayLiFiDecoder.NoLiFiDataDecoded.selector);
        helper.decodeLiFiDataOrRevert(veryShortCalldata);
    }

    // Test cases for decodeLiFiDataOrRevert
    function test_DecodeOrRevert_Success_BridgeAndSwap() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.hasSourceSwaps = true;
        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, singleSwapData, baseAcrossData));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall);

        assertEq(
            decodedBridgeData.transactionId, localBridgeData.transactionId, "DOR01: BridgeData.transactionId mismatch"
        );
        assertEq(decodedSwapData.length, singleSwapData.length, "DOR01: SwapData length mismatch");
        assertEq(decodedSwapData[0].callTo, singleSwapData[0].callTo, "DOR01: SwapData[0].callTo mismatch");
    }
}
