// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {AnypayLiFiDecoder} from "src/libraries/AnypayLiFiDecoder.sol";

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

contract AnypayDecoderTestHelperForAcross {
    function mockDecodeBridgeAndSwapData(bytes memory data)
        external
        pure
        returns (bool success, ILiFi.BridgeData memory bridgeDataOut, LibSwap.SwapData[] memory swapDataOut)
    {
        return AnypayLiFiDecoder.tryDecodeBridgeAndSwapData(data);
    }

    function mockDecodeLiFiDataOrRevert(bytes memory data)
        external
        pure
        returns (ILiFi.BridgeData memory finalBridgeData, LibSwap.SwapData[] memory finalSwapDataArray)
    {
        return AnypayLiFiDecoder.decodeLiFiDataOrRevert(data);
    }
}

contract MockAcrossFacetV3 {
    event StartBridgeCalled(bytes32 indexed transactionId, address receiver);
    event SwapAndStartBridgeCalled(bytes32 indexed transactionId, address receiver);
    event CallReverted(bytes4 selector, bytes reason);

    // Mocks `startBridgeTokensViaAcrossV3`
    function mockStartBridge(ILiFi.BridgeData memory _bridgeData, AcrossV3Data calldata _acrossData) external payable {
        console.log("MockAcrossFacetV3::mockStartBridge received receiver:", _bridgeData.receiver);
        emit StartBridgeCalled(_bridgeData.transactionId, _bridgeData.receiver);
    }

    // Mocks `swapAndStartBridgeTokensViaAcrossV3`
    function mockSwapAndStartBridge(
        ILiFi.BridgeData memory _bridgeData,
        LibSwap.SwapData[] calldata _swapData,
        AcrossV3Data calldata _acrossData
    ) external payable {
        console.log("MockAcrossFacetV3::mockSwapAndStartBridge received receiver:", _bridgeData.receiver);
        emit SwapAndStartBridgeCalled(_bridgeData.transactionId, _bridgeData.receiver);
    }

    receive() external payable {}
}

contract MockAcrossFacetV3Test is Test {
    MockAcrossFacetV3 public mockFacet;
    address public user = makeAddr("user");
    address public originalReceiver = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);

    AnypayDecoderTestHelperForAcross public decoderHelper;

    ILiFi.BridgeData internal baseBridgeData = ILiFi.BridgeData({
        transactionId: bytes32(uint256(1)),
        bridge: "across",
        integrator: "testWrap",
        referrer: address(0),
        sendingAssetId: address(0x111111111117dC0aa78b770fA6A738034120C302),
        receiver: originalReceiver,
        minAmount: 1 ether,
        destinationChainId: 10,
        hasSourceSwaps: false,
        hasDestinationCall: false
    });

    AcrossV3Data internal baseAcrossData = AcrossV3Data({
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

    function setUp() public {
        mockFacet = new MockAcrossFacetV3();
        decoderHelper = new AnypayDecoderTestHelperForAcross();
        deal(user, 10 ether);
    }

    function test_AnypayDecoder_TryDecode_MockAcross_StartBridge() public {
        ILiFi.BridgeData memory bridgeDataInput = baseBridgeData;
        AcrossV3Data memory acrossDataInput = baseAcrossData;
        bridgeDataInput.transactionId = bytes32(uint256(0xDEC0DE01));

        bytes memory encodedCallForAcross =
            abi.encodeCall(mockFacet.mockStartBridge, (bridgeDataInput, acrossDataInput));

        (bool success, ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            decoderHelper.mockDecodeBridgeAndSwapData(encodedCallForAcross);

        assertTrue(success, "AD_ACROSS_01: Decoding mockStartBridge calldata should succeed");

        assertEq(
            decodedBridgeData.transactionId,
            bridgeDataInput.transactionId,
            "AD_ACROSS_01: Decoded BridgeData transactionId mismatch"
        );
        assertEq(decodedBridgeData.bridge, bridgeDataInput.bridge, "AD_ACROSS_01: Decoded BridgeData bridge mismatch");
        assertEq(
            decodedBridgeData.integrator,
            bridgeDataInput.integrator,
            "AD_ACROSS_01: Decoded BridgeData integrator mismatch"
        );
        assertEq(
            decodedBridgeData.receiver, bridgeDataInput.receiver, "AD_ACROSS_01: Decoded BridgeData receiver mismatch"
        );
        assertEq(
            decodedBridgeData.sendingAssetId,
            bridgeDataInput.sendingAssetId,
            "AD_ACROSS_01: Decoded BridgeData sendingAssetId mismatch"
        );
        assertEq(
            decodedBridgeData.minAmount,
            bridgeDataInput.minAmount,
            "AD_ACROSS_01: Decoded BridgeData minAmount mismatch"
        );
        assertEq(
            decodedBridgeData.destinationChainId,
            bridgeDataInput.destinationChainId,
            "AD_ACROSS_01: Decoded BridgeData destinationChainId mismatch"
        );
        assertFalse(
            bridgeDataInput.hasSourceSwaps,
            "AD_ACROSS_01: Input BridgeData hasSourceSwaps should be false for this test case"
        );
        assertEq(decodedSwapData.length, 0, "AD_ACROSS_01: Decoded SwapData array should be empty for mockStartBridge");
    }

    function test_AnypayDecoder_TryDecode_MockAcross_SwapAndStartBridge() public {
        ILiFi.BridgeData memory bridgeDataInput = baseBridgeData;
        AcrossV3Data memory acrossDataInput = baseAcrossData;
        bridgeDataInput.transactionId = bytes32(uint256(0xDEC0DE02));
        bridgeDataInput.hasSourceSwaps = true;

        LibSwap.SwapData[] memory swapDataInput = new LibSwap.SwapData[](1);
        swapDataInput[0] = LibSwap.SwapData({
            callTo: address(0xdeadbeef),
            approveTo: address(0xdeadbeef),
            sendingAssetId: bridgeDataInput.sendingAssetId,
            receivingAssetId: address(0xcafebabe),
            fromAmount: bridgeDataInput.minAmount,
            callData: hex"010203",
            requiresDeposit: true
        });

        bytes memory encodedCallForAcross =
            abi.encodeCall(mockFacet.mockSwapAndStartBridge, (bridgeDataInput, swapDataInput, acrossDataInput));

        (bool success, ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            decoderHelper.mockDecodeBridgeAndSwapData(encodedCallForAcross);

        assertTrue(success, "AD_ACROSS_02: Decoding mockSwapAndStartBridge calldata should succeed");

        assertEq(
            decodedBridgeData.transactionId,
            bridgeDataInput.transactionId,
            "AD_ACROSS_02: Decoded BridgeData transactionId mismatch"
        );
        assertEq(decodedBridgeData.bridge, bridgeDataInput.bridge, "AD_ACROSS_02: Decoded BridgeData bridge mismatch");
        assertTrue(decodedBridgeData.hasSourceSwaps, "AD_ACROSS_02: Decoded BridgeData hasSourceSwaps should be true");

        assertEq(decodedSwapData.length, swapDataInput.length, "AD_ACROSS_02: Decoded SwapData array length mismatch");
        if (decodedSwapData.length > 0 && swapDataInput.length > 0) {
            assertEq(
                decodedSwapData[0].callTo, swapDataInput[0].callTo, "AD_ACROSS_02: Decoded SwapData[0].callTo mismatch"
            );
            assertEq(
                decodedSwapData[0].approveTo,
                swapDataInput[0].approveTo,
                "AD_ACROSS_02: Decoded SwapData[0].approveTo mismatch"
            );
            assertEq(
                decodedSwapData[0].sendingAssetId,
                swapDataInput[0].sendingAssetId,
                "AD_ACROSS_02: Decoded SwapData[0].sendingAssetId mismatch"
            );
            assertEq(
                decodedSwapData[0].receivingAssetId,
                swapDataInput[0].receivingAssetId,
                "AD_ACROSS_02: Decoded SwapData[0].receivingAssetId mismatch"
            );
            assertEq(
                decodedSwapData[0].fromAmount,
                swapDataInput[0].fromAmount,
                "AD_ACROSS_02: Decoded SwapData[0].fromAmount mismatch"
            );
            assertEq(
                decodedSwapData[0].callData,
                swapDataInput[0].callData,
                "AD_ACROSS_02: Decoded SwapData[0].callData mismatch"
            );
            assertEq(
                decodedSwapData[0].requiresDeposit,
                swapDataInput[0].requiresDeposit,
                "AD_ACROSS_02: Decoded SwapData[0].requiresDeposit mismatch"
            );
        }
    }

    function test_AnypayDecoder_DecodeOrRevert_MockAcross_SwapAndStartBridge() public {
        ILiFi.BridgeData memory bridgeDataInput = baseBridgeData;
        AcrossV3Data memory acrossDataInput = baseAcrossData;
        bridgeDataInput.transactionId = bytes32(uint256(0xDEC0DE03));
        bridgeDataInput.hasSourceSwaps = true;

        LibSwap.SwapData[] memory swapDataInput = new LibSwap.SwapData[](1);
        swapDataInput[0] = LibSwap.SwapData({
            callTo: address(0x12345),
            approveTo: address(0x12345),
            sendingAssetId: bridgeDataInput.sendingAssetId,
            receivingAssetId: address(0x6789A),
            fromAmount: bridgeDataInput.minAmount,
            callData: hex"abcdef",
            requiresDeposit: false
        });

        bytes memory encodedCallForAcross =
            abi.encodeCall(mockFacet.mockSwapAndStartBridge, (bridgeDataInput, swapDataInput, acrossDataInput));

        (ILiFi.BridgeData memory decodedBridgeData, LibSwap.SwapData[] memory decodedSwapData) =
            decoderHelper.mockDecodeLiFiDataOrRevert(encodedCallForAcross);

        assertTrue(true, "AD_ACROSS_03: decodeLiFiDataOrRevert should succeed for mockSwapAndStartBridge calldata");

        assertEq(
            decodedBridgeData.transactionId,
            bridgeDataInput.transactionId,
            "AD_ACROSS_03: Decoded BridgeData transactionId mismatch"
        );
        assertTrue(decodedBridgeData.hasSourceSwaps, "AD_ACROSS_03: Decoded BridgeData hasSourceSwaps should be true");

        assertEq(decodedSwapData.length, swapDataInput.length, "AD_ACROSS_03: Decoded SwapData array length mismatch");
        if (decodedSwapData.length > 0 && swapDataInput.length > 0) {
            assertEq(
                decodedSwapData[0].callTo, swapDataInput[0].callTo, "AD_ACROSS_03: Decoded SwapData[0].callTo mismatch"
            );
        }
    }
}
