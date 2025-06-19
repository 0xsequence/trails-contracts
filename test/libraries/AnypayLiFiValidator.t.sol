// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {AnypayLiFiValidator} from "@/libraries/AnypayLiFiValidator.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";

contract AnypayLiFiValidatorTest is Test {
    LibSwap.SwapData internal baseSwapData;
    ILiFi.BridgeData internal baseBridgeData;

    function setUp() public {
        baseSwapData = LibSwap.SwapData({
            callTo: address(0),
            approveTo: address(0),
            sendingAssetId: address(0),
            receivingAssetId: address(0),
            fromAmount: 0,
            callData: bytes(""),
            requiresDeposit: true
        });

        baseBridgeData = ILiFi.BridgeData({
            transactionId: keccak256("txid"),
            bridge: "some-bridge",
            integrator: "Anypay",
            referrer: address(0),
            sendingAssetId: address(0x100),
            receiver: address(0x300),
            minAmount: 100,
            destinationChainId: 1,
            hasSourceSwaps: false,
            hasDestinationCall: false
        });
    }

    // --- Tests for isSwapDataValid ---

    function test_IsSwapDataValid_WithCallTo() public view {
        LibSwap.SwapData memory swapData = baseSwapData;
        swapData.callTo = address(0x1);
        assertTrue(AnypayLiFiValidator.isSwapDataValid(swapData), "should be valid with callTo");
    }

    function test_IsSwapDataValid_WithApproveTo() public view {
        LibSwap.SwapData memory swapData = baseSwapData;
        swapData.approveTo = address(0x1);
        assertTrue(AnypayLiFiValidator.isSwapDataValid(swapData), "should be valid with approveTo");
    }

    function test_IsSwapDataValid_WithFromAmount() public view {
        LibSwap.SwapData memory swapData = baseSwapData;
        swapData.fromAmount = 1;
        assertTrue(AnypayLiFiValidator.isSwapDataValid(swapData), "should be valid with fromAmount");
    }

    function test_IsSwapDataValid_Invalid() public view {
        LibSwap.SwapData memory swapData = baseSwapData;
        assertFalse(AnypayLiFiValidator.isSwapDataValid(swapData), "should be invalid");
    }

    // --- Tests for isSwapDataArrayValid ---

    function test_IsSwapDataArrayValid_WithOneValidSwap() public view {
        LibSwap.SwapData[] memory swapDataArray = new LibSwap.SwapData[](1);
        swapDataArray[0] = baseSwapData;
        swapDataArray[0].callTo = address(0x1);
        assertTrue(AnypayLiFiValidator.isSwapDataArrayValid(swapDataArray), "should be valid with one valid swap");
    }

    function test_IsSwapDataArrayValid_WithMultipleSwaps_OneValid() public view {
        LibSwap.SwapData[] memory swapDataArray = new LibSwap.SwapData[](3);
        swapDataArray[0] = baseSwapData;
        swapDataArray[1] = baseSwapData;
        swapDataArray[1].callTo = address(0x1);
        swapDataArray[2] = baseSwapData;
        assertTrue(AnypayLiFiValidator.isSwapDataArrayValid(swapDataArray), "should be valid with one of many valid");
    }

    function test_IsSwapDataArrayValid_EmptyArray() public pure {
        LibSwap.SwapData[] memory swapDataArray = new LibSwap.SwapData[](0);
        assertFalse(AnypayLiFiValidator.isSwapDataArrayValid(swapDataArray), "should be invalid for empty array");
    }

    function test_IsSwapDataArrayValid_OnlyInvalidSwaps() public view {
        LibSwap.SwapData[] memory swapDataArray = new LibSwap.SwapData[](2);
        swapDataArray[0] = baseSwapData;
        swapDataArray[1] = baseSwapData;
        assertFalse(
            AnypayLiFiValidator.isSwapDataArrayValid(swapDataArray), "should be invalid with only invalid swaps"
        );
    }

    // --- Tests for isBridgeDataValid ---

    function test_IsBridgeDataValid_HappyPath() public view {
        assertTrue(AnypayLiFiValidator.isBridgeDataValid(baseBridgeData), "should be valid bridge data");
    }

    function test_IsBridgeDataValid_Invalid_ZeroTransactionId() public view {
        ILiFi.BridgeData memory bridgeData = baseBridgeData;
        bridgeData.transactionId = bytes32(0);
        assertFalse(AnypayLiFiValidator.isBridgeDataValid(bridgeData), "should be invalid with zero transactionId");
    }

    function test_IsBridgeDataValid_Invalid_EmptyBridge() public view {
        ILiFi.BridgeData memory bridgeData = baseBridgeData;
        bridgeData.bridge = "";
        assertFalse(AnypayLiFiValidator.isBridgeDataValid(bridgeData), "should be invalid with empty bridge");
    }

    function test_IsBridgeDataValid_Invalid_ZeroReceiver() public view {
        ILiFi.BridgeData memory bridgeData = baseBridgeData;
        bridgeData.receiver = address(0);
        assertFalse(AnypayLiFiValidator.isBridgeDataValid(bridgeData), "should be invalid with zero receiver");
    }

    function test_IsBridgeDataValid_Invalid_ZeroMinAmount() public view {
        ILiFi.BridgeData memory bridgeData = baseBridgeData;
        bridgeData.minAmount = 0;
        assertFalse(AnypayLiFiValidator.isBridgeDataValid(bridgeData), "should be invalid with zero minAmount");
    }

    function test_IsBridgeDataValid_Invalid_ZeroDestinationChainId() public view {
        ILiFi.BridgeData memory bridgeData = baseBridgeData;
        bridgeData.destinationChainId = 0;
        assertFalse(AnypayLiFiValidator.isBridgeDataValid(bridgeData), "should be invalid with zero destinationChainId");
    }

    // --- Tests for isBridgeAndSwapDataTupleValid ---

    function test_IsBridgeAndSwapDataTupleValid_HappyPath_WithSourceSwaps() public view {
        ILiFi.BridgeData memory bridgeData = baseBridgeData;
        bridgeData.hasSourceSwaps = true;
        LibSwap.SwapData[] memory swapDataArray = new LibSwap.SwapData[](1);
        swapDataArray[0] = baseSwapData;
        swapDataArray[0].callTo = address(0x1);
        assertTrue(
            AnypayLiFiValidator.isBridgeAndSwapDataTupleValid(bridgeData, swapDataArray),
            "should be valid with source swaps"
        );
    }

    function test_IsBridgeAndSwapDataTupleValid_HappyPath_NoSourceSwaps_EmptyArray() public view {
        ILiFi.BridgeData memory bridgeData = baseBridgeData;
        bridgeData.hasSourceSwaps = false;
        LibSwap.SwapData[] memory swapDataArray = new LibSwap.SwapData[](0);
        assertTrue(
            AnypayLiFiValidator.isBridgeAndSwapDataTupleValid(bridgeData, swapDataArray),
            "should be valid with no source swaps and empty array"
        );
    }

    function test_IsBridgeAndSwapDataTupleValid_HappyPath_NoSourceSwaps_InvalidSwapsArray() public view {
        ILiFi.BridgeData memory bridgeData = baseBridgeData;
        bridgeData.hasSourceSwaps = false;
        LibSwap.SwapData[] memory swapDataArray = new LibSwap.SwapData[](1);
        swapDataArray[0] = baseSwapData;
        assertTrue(
            AnypayLiFiValidator.isBridgeAndSwapDataTupleValid(bridgeData, swapDataArray),
            "should be valid with no source swaps and invalid swaps array"
        );
    }

    function test_IsBridgeAndSwapDataTupleValid_SadPath_InvalidBridgeData() public view {
        ILiFi.BridgeData memory bridgeData = baseBridgeData;
        bridgeData.transactionId = bytes32(0);
        LibSwap.SwapData[] memory swapDataArray = new LibSwap.SwapData[](0);
        assertFalse(
            AnypayLiFiValidator.isBridgeAndSwapDataTupleValid(bridgeData, swapDataArray),
            "should be invalid with invalid bridge data"
        );
    }

    function test_IsBridgeAndSwapDataTupleValid_SadPath_HasSourceSwaps_InvalidSwapArray() public view {
        ILiFi.BridgeData memory bridgeData = baseBridgeData;
        bridgeData.hasSourceSwaps = true;
        LibSwap.SwapData[] memory swapDataArray = new LibSwap.SwapData[](1);
        swapDataArray[0] = baseSwapData;
        assertFalse(
            AnypayLiFiValidator.isBridgeAndSwapDataTupleValid(bridgeData, swapDataArray),
            "should be invalid with hasSourceSwaps and invalid swap array"
        );
    }

    function test_IsBridgeAndSwapDataTupleValid_SadPath_NoSourceSwaps_ValidSwapArray() public view {
        ILiFi.BridgeData memory bridgeData = baseBridgeData;
        bridgeData.hasSourceSwaps = false;
        LibSwap.SwapData[] memory swapDataArray = new LibSwap.SwapData[](1);
        swapDataArray[0] = baseSwapData;
        swapDataArray[0].callTo = address(0x1);
        assertFalse(
            AnypayLiFiValidator.isBridgeAndSwapDataTupleValid(bridgeData, swapDataArray),
            "should be invalid with noSourceSwaps and valid swap array"
        );
    }
}
