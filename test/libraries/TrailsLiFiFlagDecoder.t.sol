// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {TrailsLiFiFlagDecoder} from "@/libraries/TrailsLiFiFlagDecoder.sol";
import {TrailsDecodingStrategy} from "@/interfaces/TrailsLiFi.sol";

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

// Helper contract to test the TrailsLiFiFlagDecoder library
contract FlagDecoderTestHelper {
    function decodeLiFiDataOrRevert(bytes calldata data, TrailsDecodingStrategy strategy)
        external
        pure
        returns (ILiFi.BridgeData memory finalBridgeData, LibSwap.SwapData[] memory finalSwapDataArray)
    {
        return TrailsLiFiFlagDecoder.decodeLiFiDataOrRevert(data, strategy);
    }

    // Mock functions for various LiFi patterns
    function mockStartBridge(ILiFi.BridgeData memory _bridgeData, AcrossV3Data calldata _acrossData) external pure {}

    function mockSingleBridgeArg(ILiFi.BridgeData memory _bridgeData) external pure {}

    function mockSwapAndStartBridge(
        ILiFi.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData,
        AcrossV3Data calldata _acrossData
    ) external pure {}

    function mockSwapTokensSingle(
        bytes32 _transactionId,
        string calldata _integrator,
        string calldata _referrer,
        address _receiver,
        uint256 _minAmountOut,
        LibSwap.SwapData calldata _swapData
    ) external pure {}

    function mockSwapTokensMultiple(
        bytes32 _transactionId,
        string calldata _integrator,
        string calldata _referrer,
        address _receiver,
        uint256 _minAmountOut,
        LibSwap.SwapData[] calldata _swapData
    ) external pure {}

    function mockUnrelatedFunction(uint256 value, bool flag) external pure {}
}

contract TrailsLiFiFlagDecoderTest is Test {
    FlagDecoderTestHelper public helper;
    address public user = makeAddr("user");
    address public originalReceiver = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);

    ILiFi.BridgeData internal baseBridgeData;
    AcrossV3Data internal baseAcrossData;
    LibSwap.SwapData[] internal singleSwapData;
    LibSwap.SwapData[] internal multipleSwapData;

    // Mock prefix data for swap functions
    bytes32 internal dummyTxId = bytes32(uint256(0xABC));
    string internal dummyIntegrator = "TestIntegrator";
    string internal dummyReferrer = "TestReferrer";
    address internal dummyReceiver = makeAddr("dummyReceiver");
    uint256 internal dummyMinAmountOut = 1 wei;

    function setUp() public {
        helper = new FlagDecoderTestHelper();

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

        multipleSwapData = new LibSwap.SwapData[](2);
        multipleSwapData[0] = singleSwapData[0];
        multipleSwapData[1] = LibSwap.SwapData({
            callTo: address(0xcafe),
            approveTo: address(0xcafe),
            sendingAssetId: address(0xbeef),
            receivingAssetId: baseBridgeData.sendingAssetId,
            fromAmount: 0.9 ether,
            callData: hex"1234",
            requiresDeposit: true
        });
    }

    function test_BridgeDataAndSwapDataTuple_Success_WithSwaps() public view {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x7001));
        localBridgeData.hasSourceSwaps = true;

        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, singleSwapData, baseAcrossData));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall, TrailsDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);

        assertEq(decodedBridgeData.transactionId, localBridgeData.transactionId, "BridgeData transactionId mismatch");
        assertEq(decodedBridgeData.bridge, localBridgeData.bridge, "BridgeData bridge mismatch");
        assertEq(decodedSwapData.length, singleSwapData.length, "SwapData length mismatch");
        assertEq(decodedSwapData[0].callTo, singleSwapData[0].callTo, "SwapData[0].callTo mismatch");
    }

    function test_BridgeDataAndSwapDataTuple_Success_WithEmptySwaps() public view {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x7002));
        localBridgeData.hasSourceSwaps = false;
        LibSwap.SwapData[] memory emptySwapDataArray = new LibSwap.SwapData[](0);

        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, emptySwapDataArray, baseAcrossData));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall, TrailsDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);

        assertEq(decodedBridgeData.transactionId, localBridgeData.transactionId, "BridgeData transactionId mismatch");
        assertEq(decodedSwapData.length, 0, "Expected empty SwapData array");
    }

    function test_BridgeDataAndSwapDataTuple_DoesNotRevert_OnInvalidBridgeData() public {
        ILiFi.BridgeData memory invalidBridgeData = baseBridgeData;
        invalidBridgeData.transactionId = bytes32(0);
        invalidBridgeData.bridge = "";

        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (invalidBridgeData, singleSwapData, baseAcrossData));

        helper.decodeLiFiDataOrRevert(encodedCall, TrailsDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);
    }

    function test_BridgeDataAndSwapDataTuple_DoesNotRevert_OnInconsistentSwapFlag() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.hasSourceSwaps = true;
        LibSwap.SwapData[] memory emptySwapDataArray = new LibSwap.SwapData[](0);

        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, emptySwapDataArray, baseAcrossData));

        helper.decodeLiFiDataOrRevert(encodedCall, TrailsDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);
    }

    // -------------------------------------------------------------------------
    // Tests for SINGLE_BRIDGE_DATA Strategy
    // -------------------------------------------------------------------------

    function test_SingleBridgeData_Success() public view {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x8001));

        bytes memory encodedCall = abi.encodeCall(helper.mockSingleBridgeArg, (localBridgeData));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall, TrailsDecodingStrategy.SINGLE_BRIDGE_DATA);

        assertEq(decodedBridgeData.transactionId, localBridgeData.transactionId, "BridgeData transactionId mismatch");
        assertEq(decodedBridgeData.bridge, localBridgeData.bridge, "BridgeData bridge mismatch");
        assertEq(decodedSwapData.length, 0, "SwapData should be empty for SINGLE_BRIDGE_DATA strategy");
    }

    function test_SingleBridgeData_DoesNotRevert_OnInvalidBridgeData() public {
        ILiFi.BridgeData memory invalidBridgeData = baseBridgeData;
        invalidBridgeData.transactionId = bytes32(0);
        invalidBridgeData.receiver = address(0);

        bytes memory encodedCall = abi.encodeCall(helper.mockSingleBridgeArg, (invalidBridgeData));

        helper.decodeLiFiDataOrRevert(encodedCall, TrailsDecodingStrategy.SINGLE_BRIDGE_DATA);
    }

    function test_SingleBridgeData_Reverts_WrongCalldata() public {
        // Try to decode bridge+swap calldata as single bridge data
        bytes memory invalidCalldata = hex"deadbeef11111111";

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(invalidCalldata, TrailsDecodingStrategy.SINGLE_BRIDGE_DATA);
    }

    // -------------------------------------------------------------------------
    // Tests for SWAP_DATA_ARRAY Strategy
    // -------------------------------------------------------------------------

    function test_SwapDataArray_Success_SingleSwap() public view {
        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensMultiple,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, singleSwapData)
        );

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall, TrailsDecodingStrategy.SWAP_DATA_ARRAY);

        assertEq(decodedBridgeData.transactionId, bytes32(0), "BridgeData should be empty for SWAP_DATA_ARRAY strategy");
        assertEq(decodedSwapData.length, singleSwapData.length, "SwapData array length mismatch");
        assertEq(decodedSwapData[0].callTo, singleSwapData[0].callTo, "SwapData[0].callTo mismatch");
    }

    function test_SwapDataArray_Success_MultipleSwaps() public view {
        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensMultiple,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, multipleSwapData)
        );

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall, TrailsDecodingStrategy.SWAP_DATA_ARRAY);

        assertEq(decodedBridgeData.transactionId, bytes32(0), "BridgeData should be empty");
        assertEq(decodedSwapData.length, multipleSwapData.length, "SwapData array length mismatch");
        assertEq(decodedSwapData[0].callTo, multipleSwapData[0].callTo, "SwapData[0].callTo mismatch");
        assertEq(decodedSwapData[1].callTo, multipleSwapData[1].callTo, "SwapData[1].callTo mismatch");
    }

    function test_SwapDataArray_DoesNotRevert_OnEmptySwapData() public {
        LibSwap.SwapData[] memory emptySwapData = new LibSwap.SwapData[](0);
        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensMultiple,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, emptySwapData)
        );

        helper.decodeLiFiDataOrRevert(encodedCall, TrailsDecodingStrategy.SWAP_DATA_ARRAY);
    }

    function test_SwapDataArray_DoesNotRevert_OnInvalidSwapData() public {
        LibSwap.SwapData[] memory invalidSwapData = new LibSwap.SwapData[](1);
        invalidSwapData[0] = LibSwap.SwapData({
            callTo: address(0),
            approveTo: address(0),
            sendingAssetId: address(0),
            receivingAssetId: address(0),
            fromAmount: 0,
            callData: hex"",
            requiresDeposit: false
        });

        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensMultiple,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, invalidSwapData)
        );

        helper.decodeLiFiDataOrRevert(encodedCall, TrailsDecodingStrategy.SWAP_DATA_ARRAY);
    }

    function test_SwapDataArray_Reverts_CalldataTooShort() public {
        bytes memory shortCalldata = hex"deadbeef01020304";

        vm.expectRevert(TrailsLiFiFlagDecoder.CalldataTooShortForPayload.selector);
        helper.decodeLiFiDataOrRevert(shortCalldata, TrailsDecodingStrategy.SWAP_DATA_ARRAY);
    }

    // -------------------------------------------------------------------------
    // Tests for SINGLE_SWAP_DATA Strategy
    // -------------------------------------------------------------------------

    function test_SingleSwapData_Success() public view {
        LibSwap.SwapData memory singleSwap = singleSwapData[0];
        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensSingle,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, singleSwap)
        );

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall, TrailsDecodingStrategy.SINGLE_SWAP_DATA);

        assertEq(
            decodedBridgeData.transactionId, bytes32(0), "BridgeData should be empty for SINGLE_SWAP_DATA strategy"
        );
        assertEq(decodedSwapData.length, 1, "SwapData should be converted to array of length 1");
        assertEq(decodedSwapData[0].callTo, singleSwap.callTo, "SwapData.callTo mismatch");
        assertEq(decodedSwapData[0].fromAmount, singleSwap.fromAmount, "SwapData.fromAmount mismatch");
    }

    function test_SingleSwapData_DoesNotRevert_OnInvalidSwapData() public {
        LibSwap.SwapData memory invalidSwap = LibSwap.SwapData({
            callTo: address(0),
            approveTo: address(0),
            sendingAssetId: address(0),
            receivingAssetId: address(0),
            fromAmount: 0,
            callData: hex"",
            requiresDeposit: false
        });

        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensSingle,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, invalidSwap)
        );

        helper.decodeLiFiDataOrRevert(encodedCall, TrailsDecodingStrategy.SINGLE_SWAP_DATA);
    }

    function test_SingleSwapData_Reverts_CalldataTooShort() public {
        bytes memory shortCalldata = hex"deadbeef";

        vm.expectRevert(TrailsLiFiFlagDecoder.CalldataTooShortForPayload.selector);
        helper.decodeLiFiDataOrRevert(shortCalldata, TrailsDecodingStrategy.SINGLE_SWAP_DATA);
    }

    function test_SingleSwapData_Reverts_WrongCalldata() public {
        // Try to decode array calldata as single swap data
        bytes memory wrongEncodedCall = abi.encodeCall(
            helper.mockSwapTokensMultiple,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, multipleSwapData)
        );

        vm.expectRevert(); // Should revert during abi.decode
        helper.decodeLiFiDataOrRevert(wrongEncodedCall, TrailsDecodingStrategy.SINGLE_SWAP_DATA);
    }

    // -------------------------------------------------------------------------
    // Edge Case Tests
    // -------------------------------------------------------------------------

    function test_EmptyCalldata_AllStrategies() public {
        bytes memory emptyCalldata = hex"";

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(emptyCalldata, TrailsDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(emptyCalldata, TrailsDecodingStrategy.SINGLE_BRIDGE_DATA);

        vm.expectRevert(TrailsLiFiFlagDecoder.CalldataTooShortForPayload.selector);
        helper.decodeLiFiDataOrRevert(emptyCalldata, TrailsDecodingStrategy.SWAP_DATA_ARRAY);

        vm.expectRevert(TrailsLiFiFlagDecoder.CalldataTooShortForPayload.selector);
        helper.decodeLiFiDataOrRevert(emptyCalldata, TrailsDecodingStrategy.SINGLE_SWAP_DATA);
    }

    function test_VeryShortCalldata_AllStrategies() public {
        bytes memory shortCalldata = hex"deadbeef";

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(shortCalldata, TrailsDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(shortCalldata, TrailsDecodingStrategy.SINGLE_BRIDGE_DATA);

        vm.expectRevert(TrailsLiFiFlagDecoder.CalldataTooShortForPayload.selector);
        helper.decodeLiFiDataOrRevert(shortCalldata, TrailsDecodingStrategy.SWAP_DATA_ARRAY);

        vm.expectRevert(TrailsLiFiFlagDecoder.CalldataTooShortForPayload.selector);
        helper.decodeLiFiDataOrRevert(shortCalldata, TrailsDecodingStrategy.SINGLE_SWAP_DATA);
    }

    function test_UnrelatedCalldata_AllStrategies() public {
        bytes memory unrelatedCalldata = abi.encodeCall(helper.mockUnrelatedFunction, (123456, true));

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(unrelatedCalldata, TrailsDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(unrelatedCalldata, TrailsDecodingStrategy.SINGLE_BRIDGE_DATA);

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(unrelatedCalldata, TrailsDecodingStrategy.SWAP_DATA_ARRAY);

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(unrelatedCalldata, TrailsDecodingStrategy.SINGLE_SWAP_DATA);
    }

    function test_GetMemorySlice_OutOfBounds() public {
        // This tests the SliceOutOfBounds error indirectly through the main function
        bytes memory data = hex"deadbeef";

        // Create calldata that would cause out of bounds access
        bytes memory malformedCalldata = abi.encodePacked(bytes4(0x12345678), data);

        // This should eventually hit SliceOutOfBounds when trying to process
        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(malformedCalldata, TrailsDecodingStrategy.SINGLE_BRIDGE_DATA);
    }

    function test_GasUsage_BridgeDataAndSwapDataTuple() public view {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.hasSourceSwaps = true;
        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, singleSwapData, baseAcrossData));

        uint256 gasBefore = gasleft();
        helper.decodeLiFiDataOrRevert(encodedCall, TrailsDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for BRIDGE_DATA_AND_SWAP_DATA_TUPLE:", gasUsed);
        assertLt(gasUsed, 50000, "Gas usage should be reasonable");
    }

    function test_GasUsage_SwapDataArray() public view {
        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensMultiple,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, multipleSwapData)
        );

        uint256 gasBefore = gasleft();
        helper.decodeLiFiDataOrRevert(encodedCall, TrailsDecodingStrategy.SWAP_DATA_ARRAY);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for SWAP_DATA_ARRAY:", gasUsed);
        assertLt(gasUsed, 50000, "Gas usage should be reasonable");
    }

    function testFuzz_BridgeDataTransactionId(bytes32 txId) public view {
        vm.assume(txId != bytes32(0)); // Must be non-zero for valid bridge data

        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = txId;

        bytes memory encodedCall = abi.encodeCall(helper.mockSingleBridgeArg, (localBridgeData));

        (ILiFi.BridgeData memory decodedBridgeData,) =
            helper.decodeLiFiDataOrRevert(encodedCall, TrailsDecodingStrategy.SINGLE_BRIDGE_DATA);

        assertEq(decodedBridgeData.transactionId, txId, "Transaction ID should match");
    }

    function testFuzz_SwapDataAmount(uint256 amount) public view {
        vm.assume(amount > 0); // Must be non-zero for valid swap data

        LibSwap.SwapData memory swapData = singleSwapData[0];
        swapData.fromAmount = amount;

        LibSwap.SwapData[] memory swapArray = new LibSwap.SwapData[](1);
        swapArray[0] = swapData;

        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensMultiple,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, swapArray)
        );

        (, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall, TrailsDecodingStrategy.SWAP_DATA_ARRAY);

        assertEq(decodedSwapData[0].fromAmount, amount, "Swap amount should match");
    }
}
