// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {AnypayExecutionInfoInterpreter, AnypayExecutionInfo} from "@/libraries/AnypayExecutionInfoInterpreter.sol";
import {AnypayLiFiInterpreter} from "@/libraries/AnypayLiFiInterpreter.sol";

contract AnypayLiFiInterpreterTest is Test {
    // Mock data for ILiFi.BridgeData
    ILiFi.BridgeData internal mockBridgeData;

    // Mock data for LibSwap.SwapData
    LibSwap.SwapData[] internal mockSwapDataArray;
    LibSwap.SwapData internal mockSingleSwapData;

    // Constants for mock data
    bytes32 constant MOCK_TRANSACTION_ID = bytes32(uint256(0xABCDEF1234567890));
    uint256 constant MOCK_DEST_CHAIN_ID = 137; // e.g., Polygon
    address constant MOCK_SENDING_ASSET_BRIDGE = address(0x1111111111111111111111111111111111111111);
    uint256 constant MOCK_MIN_AMOUNT_BRIDGE = 1000 * 1e18; // 1000 tokens
    address constant MOCK_SENDING_ASSET_SWAP = address(0x2222222222222222222222222222222222222222);
    uint256 constant MOCK_FROM_AMOUNT_SWAP = 500 * 1e18; // 500 tokens
    address constant MOCK_RECEIVER = address(0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa);
    address constant MOCK_CALL_TO_SWAP = address(0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB);
    address constant MOCK_APPROVE_TO_SWAP = address(0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC);
    address constant MOCK_RECEIVING_ASSET_SWAP = address(0xDDdDddDdDdddDDddDDddDDDDdDdDDdDDdDDDDDDd);

    function setUp() public {
        mockBridgeData = ILiFi.BridgeData({
            transactionId: MOCK_TRANSACTION_ID,
            bridge: "TestBridge",
            integrator: "TestIntegrator",
            referrer: address(0x0), // Not used by the library function
            sendingAssetId: MOCK_SENDING_ASSET_BRIDGE,
            receiver: MOCK_RECEIVER,
            minAmount: MOCK_MIN_AMOUNT_BRIDGE,
            destinationChainId: MOCK_DEST_CHAIN_ID,
            hasSourceSwaps: false, // Default, will be overridden in specific tests
            hasDestinationCall: false // Not used by the library function
        });

        mockSingleSwapData = LibSwap.SwapData({
            callTo: MOCK_CALL_TO_SWAP,
            approveTo: MOCK_APPROVE_TO_SWAP,
            sendingAssetId: MOCK_SENDING_ASSET_SWAP,
            receivingAssetId: MOCK_RECEIVING_ASSET_SWAP,
            fromAmount: MOCK_FROM_AMOUNT_SWAP,
            callData: hex"", // Not used by the library function
            requiresDeposit: false // Not used by the library function
        });
    }

    function test_GetOriginSwapInfo_WithSourceSwaps() public {
        mockBridgeData.hasSourceSwaps = true;

        // Prepare swapData array with one swap
        mockSwapDataArray = new LibSwap.SwapData[](1);
        mockSwapDataArray[0] = mockSingleSwapData;

        AnypayExecutionInfo memory result = AnypayLiFiInterpreter.getOriginSwapInfo(mockBridgeData, mockSwapDataArray);

        assertEq(
            result.originToken, MOCK_SENDING_ASSET_SWAP, "Test Case 1 Failed: Origin token should be from swapData"
        );
        assertEq(
            result.amount, MOCK_FROM_AMOUNT_SWAP, "Test Case 1 Failed: Min amount should be from swapData's fromAmount"
        );
        assertEq(result.destinationChainId, MOCK_DEST_CHAIN_ID, "Test Case 1 Failed: Destination chain ID mismatch");
    }

    function test_GetOriginSwapInfo_NoSourceSwaps() public {
        mockBridgeData.hasSourceSwaps = false;

        // swapData can be empty or non-empty; it shouldn't be accessed if hasSourceSwaps is false.
        // Providing an empty array for this test case.
        mockSwapDataArray = new LibSwap.SwapData[](0);

        AnypayExecutionInfo memory result = AnypayLiFiInterpreter.getOriginSwapInfo(mockBridgeData, mockSwapDataArray);

        assertEq(
            result.originToken,
            MOCK_SENDING_ASSET_BRIDGE,
            "Test Case 2 Failed: Origin token should be from bridgeData's sendingAssetId"
        );
        assertEq(
            result.amount,
            MOCK_MIN_AMOUNT_BRIDGE,
            "Test Case 2 Failed: Min amount should be from bridgeData's minAmount"
        );
        assertEq(result.destinationChainId, MOCK_DEST_CHAIN_ID, "Test Case 2 Failed: Destination chain ID mismatch");
    }

    // function test_GetOriginSwapInfo_Revert_EmptySwapData_WithSourceSwaps() public {
    //     mockBridgeData.hasSourceSwaps = true;

    //     // Prepare an empty swapData array
    //     mockSwapDataArray = new LibSwap.SwapData[](0);

    //     // Expect revert with the custom error EmptySwapData
    //     vm.expectRevert();
    //     AnypayLiFiInterpreter.getOriginSwapInfo(mockBridgeData, mockSwapDataArray);
    // }

    function test_GetOriginSwapInfo_WithSourceSwaps_MultipleSwapsInArray() public {
        mockBridgeData.hasSourceSwaps = true;

        // Prepare swapData array with multiple swaps, only the first should be used
        mockSwapDataArray = new LibSwap.SwapData[](2);
        mockSwapDataArray[0] = mockSingleSwapData;
        // Second swap data (should be ignored by the current logic)
        mockSwapDataArray[1] = LibSwap.SwapData({
            callTo: address(0xDEAD),
            approveTo: address(0xDEAD),
            sendingAssetId: address(0xDEAD),
            receivingAssetId: address(0xDEAD),
            fromAmount: 1 wei,
            callData: hex"DE",
            requiresDeposit: true
        });

        AnypayExecutionInfo memory result = AnypayLiFiInterpreter.getOriginSwapInfo(mockBridgeData, mockSwapDataArray);

        assertEq(
            result.originToken,
            MOCK_SENDING_ASSET_SWAP,
            "Test Case 4 Failed: Origin token should be from the first swapData item"
        );
        assertEq(
            result.amount,
            MOCK_FROM_AMOUNT_SWAP,
            "Test Case 4 Failed: Min amount should be from the first swapData item's fromAmount"
        );
        assertEq(result.destinationChainId, MOCK_DEST_CHAIN_ID, "Test Case 4 Failed: Destination chain ID mismatch");
    }
}
