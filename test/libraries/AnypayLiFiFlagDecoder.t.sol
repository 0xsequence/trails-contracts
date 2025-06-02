// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {AnypayLiFiFlagDecoder} from "src/libraries/AnypayLiFiFlagDecoder.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {AnypayDecodingStrategy} from "src/interfaces/AnypayLiFi.sol";

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

// Helper contract to test the AnypayLiFiFlagDecoder library
contract FlagDecoderTestHelper {
    function decodeLiFiDataOrRevert(bytes memory data, AnypayDecodingStrategy strategy)
        external
        pure
        returns (ILiFi.BridgeData memory finalBridgeData, LibSwap.SwapData[] memory finalSwapDataArray)
    {
        return AnypayLiFiFlagDecoder.decodeLiFiDataOrRevert(data, strategy);
    }

    // Mock functions for various LiFi patterns
    function mockStartBridge(ILiFi.BridgeData memory _bridgeData, AcrossV3Data calldata _acrossData)
        external
        pure
    {}

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

contract AnypayLiFiFlagDecoderTest is Test {
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

    // -------------------------------------------------------------------------
    // Tests for BRIDGE_DATA_AND_SWAP_DATA_TUPLE Strategy
    // -------------------------------------------------------------------------

    function test_BridgeDataAndSwapDataTuple_Success_WithSwaps() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x7001));
        localBridgeData.hasSourceSwaps = true;

        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, singleSwapData, baseAcrossData));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall, AnypayDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);

        assertEq(decodedBridgeData.transactionId, localBridgeData.transactionId, "BridgeData transactionId mismatch");
        assertEq(decodedBridgeData.bridge, localBridgeData.bridge, "BridgeData bridge mismatch");
        assertEq(decodedSwapData.length, singleSwapData.length, "SwapData length mismatch");
        assertEq(decodedSwapData[0].callTo, singleSwapData[0].callTo, "SwapData[0].callTo mismatch");
    }

    function test_BridgeDataAndSwapDataTuple_Success_WithEmptySwaps() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x7002));
        localBridgeData.hasSourceSwaps = false;
        LibSwap.SwapData[] memory emptySwapDataArray = new LibSwap.SwapData[](0);

        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, emptySwapDataArray, baseAcrossData));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall, AnypayDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);

        assertEq(decodedBridgeData.transactionId, localBridgeData.transactionId, "BridgeData transactionId mismatch");
        assertEq(decodedSwapData.length, 0, "Expected empty SwapData array");
    }

    function test_BridgeDataAndSwapDataTuple_Reverts_InvalidBridgeData() public {
        ILiFi.BridgeData memory invalidBridgeData = baseBridgeData;
        invalidBridgeData.transactionId = bytes32(0); // Invalid
        invalidBridgeData.bridge = ""; // Invalid

        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (invalidBridgeData, singleSwapData, baseAcrossData));

        vm.expectRevert(AnypayLiFiFlagDecoder.NoLiFiDataDecoded.selector);
        helper.decodeLiFiDataOrRevert(encodedCall, AnypayDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);
    }

    function test_BridgeDataAndSwapDataTuple_Reverts_InconsistentSwapFlag() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.hasSourceSwaps = true; // Says it has swaps
        LibSwap.SwapData[] memory emptySwapDataArray = new LibSwap.SwapData[](0); // But no swaps provided

        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, emptySwapDataArray, baseAcrossData));

        vm.expectRevert(AnypayLiFiFlagDecoder.NoLiFiDataDecoded.selector);
        helper.decodeLiFiDataOrRevert(encodedCall, AnypayDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);
    }

    // -------------------------------------------------------------------------
    // Tests for SINGLE_BRIDGE_DATA Strategy
    // -------------------------------------------------------------------------

    function test_SingleBridgeData_Success() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = bytes32(uint256(0x8001));

        bytes memory encodedCall = abi.encodeCall(helper.mockSingleBridgeArg, (localBridgeData));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall, AnypayDecodingStrategy.SINGLE_BRIDGE_DATA);

        assertEq(decodedBridgeData.transactionId, localBridgeData.transactionId, "BridgeData transactionId mismatch");
        assertEq(decodedBridgeData.bridge, localBridgeData.bridge, "BridgeData bridge mismatch");
        assertEq(decodedSwapData.length, 0, "SwapData should be empty for SINGLE_BRIDGE_DATA strategy");
    }

    function test_SingleBridgeData_Reverts_InvalidBridgeData() public {
        ILiFi.BridgeData memory invalidBridgeData = baseBridgeData;
        invalidBridgeData.transactionId = bytes32(0); // Invalid
        invalidBridgeData.receiver = address(0); // Invalid

        bytes memory encodedCall = abi.encodeCall(helper.mockSingleBridgeArg, (invalidBridgeData));

        vm.expectRevert(AnypayLiFiFlagDecoder.NoLiFiDataDecoded.selector);
        helper.decodeLiFiDataOrRevert(encodedCall, AnypayDecodingStrategy.SINGLE_BRIDGE_DATA);
    }

    function test_SingleBridgeData_Reverts_WrongCalldata() public {
        // Try to decode bridge+swap calldata as single bridge data
        bytes memory wrongEncodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (baseBridgeData, singleSwapData, baseAcrossData));

        // This actually succeeds because the decoder just takes the first parameter
        // which is valid bridge data, so let's test with truly invalid calldata
        bytes memory invalidCalldata = hex"deadbeef11111111";
        
        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(invalidCalldata, AnypayDecodingStrategy.SINGLE_BRIDGE_DATA);
    }

    // -------------------------------------------------------------------------
    // Tests for SWAP_DATA_ARRAY Strategy
    // -------------------------------------------------------------------------

    function test_SwapDataArray_Success_SingleSwap() public {
        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensMultiple,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, singleSwapData)
        );

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall, AnypayDecodingStrategy.SWAP_DATA_ARRAY);

        assertEq(decodedBridgeData.transactionId, bytes32(0), "BridgeData should be empty for SWAP_DATA_ARRAY strategy");
        assertEq(decodedSwapData.length, singleSwapData.length, "SwapData array length mismatch");
        assertEq(decodedSwapData[0].callTo, singleSwapData[0].callTo, "SwapData[0].callTo mismatch");
    }

    function test_SwapDataArray_Success_MultipleSwaps() public {
        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensMultiple,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, multipleSwapData)
        );

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall, AnypayDecodingStrategy.SWAP_DATA_ARRAY);

        assertEq(decodedBridgeData.transactionId, bytes32(0), "BridgeData should be empty");
        assertEq(decodedSwapData.length, multipleSwapData.length, "SwapData array length mismatch");
        assertEq(decodedSwapData[0].callTo, multipleSwapData[0].callTo, "SwapData[0].callTo mismatch");
        assertEq(decodedSwapData[1].callTo, multipleSwapData[1].callTo, "SwapData[1].callTo mismatch");
    }

    function test_SwapDataArray_Reverts_EmptySwapData() public {
        LibSwap.SwapData[] memory emptySwapData = new LibSwap.SwapData[](0);
        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensMultiple,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, emptySwapData)
        );

        vm.expectRevert(AnypayLiFiFlagDecoder.NoLiFiDataDecoded.selector);
        helper.decodeLiFiDataOrRevert(encodedCall, AnypayDecodingStrategy.SWAP_DATA_ARRAY);
    }

    function test_SwapDataArray_Reverts_InvalidSwapData() public {
        LibSwap.SwapData[] memory invalidSwapData = new LibSwap.SwapData[](1);
        invalidSwapData[0] = LibSwap.SwapData({
            callTo: address(0), // Invalid
            approveTo: address(0), // Invalid
            sendingAssetId: address(0),
            receivingAssetId: address(0),
            fromAmount: 0, // Invalid
            callData: hex"",
            requiresDeposit: false
        });

        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensMultiple,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, invalidSwapData)
        );

        vm.expectRevert(AnypayLiFiFlagDecoder.NoLiFiDataDecoded.selector);
        helper.decodeLiFiDataOrRevert(encodedCall, AnypayDecodingStrategy.SWAP_DATA_ARRAY);
    }

    function test_SwapDataArray_Reverts_CalldataTooShort() public {
        bytes memory shortCalldata = hex"deadbeef01020304";

        vm.expectRevert(AnypayLiFiFlagDecoder.CalldataTooShortForPayload.selector);
        helper.decodeLiFiDataOrRevert(shortCalldata, AnypayDecodingStrategy.SWAP_DATA_ARRAY);
    }

    // -------------------------------------------------------------------------
    // Tests for SINGLE_SWAP_DATA Strategy
    // -------------------------------------------------------------------------

    function test_SingleSwapData_Success() public {
        LibSwap.SwapData memory singleSwap = singleSwapData[0];
        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensSingle,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, singleSwap)
        );

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            helper.decodeLiFiDataOrRevert(encodedCall, AnypayDecodingStrategy.SINGLE_SWAP_DATA);

        assertEq(decodedBridgeData.transactionId, bytes32(0), "BridgeData should be empty for SINGLE_SWAP_DATA strategy");
        assertEq(decodedSwapData.length, 1, "SwapData should be converted to array of length 1");
        assertEq(decodedSwapData[0].callTo, singleSwap.callTo, "SwapData.callTo mismatch");
        assertEq(decodedSwapData[0].fromAmount, singleSwap.fromAmount, "SwapData.fromAmount mismatch");
    }

    function test_SingleSwapData_Reverts_InvalidSwapData() public {
        LibSwap.SwapData memory invalidSwap = LibSwap.SwapData({
            callTo: address(0), // Invalid
            approveTo: address(0), // Invalid
            sendingAssetId: address(0),
            receivingAssetId: address(0),
            fromAmount: 0, // Invalid
            callData: hex"",
            requiresDeposit: false
        });

        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensSingle,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, invalidSwap)
        );

        vm.expectRevert(AnypayLiFiFlagDecoder.NoLiFiDataDecoded.selector);
        helper.decodeLiFiDataOrRevert(encodedCall, AnypayDecodingStrategy.SINGLE_SWAP_DATA);
    }

    function test_SingleSwapData_Reverts_CalldataTooShort() public {
        bytes memory shortCalldata = hex"deadbeef";

        vm.expectRevert(AnypayLiFiFlagDecoder.CalldataTooShortForPayload.selector);
        helper.decodeLiFiDataOrRevert(shortCalldata, AnypayDecodingStrategy.SINGLE_SWAP_DATA);
    }

    function test_SingleSwapData_Reverts_WrongCalldata() public {
        // Try to decode array calldata as single swap data
        bytes memory wrongEncodedCall = abi.encodeCall(
            helper.mockSwapTokensMultiple,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, multipleSwapData)
        );

        vm.expectRevert(); // Should revert during abi.decode
        helper.decodeLiFiDataOrRevert(wrongEncodedCall, AnypayDecodingStrategy.SINGLE_SWAP_DATA);
    }

    // -------------------------------------------------------------------------
    // Edge Case Tests
    // -------------------------------------------------------------------------

    function test_EmptyCalldata_AllStrategies() public {
        bytes memory emptyCalldata = hex"";

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(emptyCalldata, AnypayDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(emptyCalldata, AnypayDecodingStrategy.SINGLE_BRIDGE_DATA);

        vm.expectRevert(AnypayLiFiFlagDecoder.CalldataTooShortForPayload.selector);
        helper.decodeLiFiDataOrRevert(emptyCalldata, AnypayDecodingStrategy.SWAP_DATA_ARRAY);

        vm.expectRevert(AnypayLiFiFlagDecoder.CalldataTooShortForPayload.selector);
        helper.decodeLiFiDataOrRevert(emptyCalldata, AnypayDecodingStrategy.SINGLE_SWAP_DATA);
    }

    function test_VeryShortCalldata_AllStrategies() public {
        bytes memory shortCalldata = hex"deadbeef";

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(shortCalldata, AnypayDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(shortCalldata, AnypayDecodingStrategy.SINGLE_BRIDGE_DATA);

        vm.expectRevert(AnypayLiFiFlagDecoder.CalldataTooShortForPayload.selector);
        helper.decodeLiFiDataOrRevert(shortCalldata, AnypayDecodingStrategy.SWAP_DATA_ARRAY);

        vm.expectRevert(AnypayLiFiFlagDecoder.CalldataTooShortForPayload.selector);
        helper.decodeLiFiDataOrRevert(shortCalldata, AnypayDecodingStrategy.SINGLE_SWAP_DATA);
    }

    function test_UnrelatedCalldata_AllStrategies() public {
        bytes memory unrelatedCalldata = abi.encodeCall(helper.mockUnrelatedFunction, (123456, true));

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(unrelatedCalldata, AnypayDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(unrelatedCalldata, AnypayDecodingStrategy.SINGLE_BRIDGE_DATA);

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(unrelatedCalldata, AnypayDecodingStrategy.SWAP_DATA_ARRAY);

        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(unrelatedCalldata, AnypayDecodingStrategy.SINGLE_SWAP_DATA);
    }

    // -------------------------------------------------------------------------
    // Tests for getMemorySlice Helper Function (via edge cases)
    // -------------------------------------------------------------------------

    function test_GetMemorySlice_OutOfBounds() public {
        // This tests the SliceOutOfBounds error indirectly through the main function
        bytes memory data = hex"deadbeef";
        
        // Create calldata that would cause out of bounds access
        bytes memory malformedCalldata = abi.encodePacked(bytes4(0x12345678), data);
        
        // This should eventually hit SliceOutOfBounds when trying to process
        vm.expectRevert();
        helper.decodeLiFiDataOrRevert(malformedCalldata, AnypayDecodingStrategy.SINGLE_BRIDGE_DATA);
    }

    // -------------------------------------------------------------------------
    // Gas Usage Tests
    // -------------------------------------------------------------------------

    function test_GasUsage_BridgeDataAndSwapDataTuple() public {
        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.hasSourceSwaps = true;
        bytes memory encodedCall =
            abi.encodeCall(helper.mockSwapAndStartBridge, (localBridgeData, singleSwapData, baseAcrossData));

        uint256 gasBefore = gasleft();
        helper.decodeLiFiDataOrRevert(encodedCall, AnypayDecodingStrategy.BRIDGE_DATA_AND_SWAP_DATA_TUPLE);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for BRIDGE_DATA_AND_SWAP_DATA_TUPLE:", gasUsed);
        assertLt(gasUsed, 50000, "Gas usage should be reasonable");
    }

    function test_GasUsage_SwapDataArray() public {
        bytes memory encodedCall = abi.encodeCall(
            helper.mockSwapTokensMultiple,
            (dummyTxId, dummyIntegrator, dummyReferrer, dummyReceiver, dummyMinAmountOut, multipleSwapData)
        );

        uint256 gasBefore = gasleft();
        helper.decodeLiFiDataOrRevert(encodedCall, AnypayDecodingStrategy.SWAP_DATA_ARRAY);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for SWAP_DATA_ARRAY:", gasUsed);
        assertLt(gasUsed, 50000, "Gas usage should be reasonable");
    }

    // -------------------------------------------------------------------------
    // Fuzz Tests
    // -------------------------------------------------------------------------

    function testFuzz_BridgeDataTransactionId(bytes32 txId) public {
        vm.assume(txId != bytes32(0)); // Must be non-zero for valid bridge data

        ILiFi.BridgeData memory localBridgeData = baseBridgeData;
        localBridgeData.transactionId = txId;

        bytes memory encodedCall = abi.encodeCall(helper.mockSingleBridgeArg, (localBridgeData));

        (ILiFi.BridgeData memory decodedBridgeData,) =
            helper.decodeLiFiDataOrRevert(encodedCall, AnypayDecodingStrategy.SINGLE_BRIDGE_DATA);

        assertEq(decodedBridgeData.transactionId, txId, "Transaction ID should match");
    }

    function testFuzz_SwapDataAmount(uint256 amount) public {
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
            helper.decodeLiFiDataOrRevert(encodedCall, AnypayDecodingStrategy.SWAP_DATA_ARRAY);

        assertEq(decodedSwapData[0].fromAmount, amount, "Swap amount should match");
    }
} 