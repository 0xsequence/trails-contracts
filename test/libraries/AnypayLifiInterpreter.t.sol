// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {AnypayLifiInterpreter, AnypayLifiInfo, EmptyLibSwapData} from "../../src/libraries/AnypayLifiInterpreter.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";

contract AnypayLifiInterpreterTest is Test {
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

        AnypayLifiInfo memory result = AnypayLifiInterpreter.getOriginSwapInfo(mockBridgeData, mockSwapDataArray);

        assertEq(
            result.originToken, MOCK_SENDING_ASSET_SWAP, "Test Case 1 Failed: Origin token should be from swapData"
        );
        assertEq(
            result.minAmount,
            MOCK_FROM_AMOUNT_SWAP,
            "Test Case 1 Failed: Min amount should be from swapData's fromAmount"
        );
        assertEq(result.destinationChainId, MOCK_DEST_CHAIN_ID, "Test Case 1 Failed: Destination chain ID mismatch");
    }

    function test_GetOriginSwapInfo_NoSourceSwaps() public {
        mockBridgeData.hasSourceSwaps = false;

        // swapData can be empty or non-empty; it shouldn't be accessed if hasSourceSwaps is false.
        // Providing an empty array for this test case.
        mockSwapDataArray = new LibSwap.SwapData[](0);

        AnypayLifiInfo memory result = AnypayLifiInterpreter.getOriginSwapInfo(mockBridgeData, mockSwapDataArray);

        assertEq(
            result.originToken,
            MOCK_SENDING_ASSET_BRIDGE,
            "Test Case 2 Failed: Origin token should be from bridgeData's sendingAssetId"
        );
        assertEq(
            result.minAmount,
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
    //     AnypayLifiInterpreter.getOriginSwapInfo(mockBridgeData, mockSwapDataArray);
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

        AnypayLifiInfo memory result = AnypayLifiInterpreter.getOriginSwapInfo(mockBridgeData, mockSwapDataArray);

        assertEq(
            result.originToken,
            MOCK_SENDING_ASSET_SWAP,
            "Test Case 4 Failed: Origin token should be from the first swapData item"
        );
        assertEq(
            result.minAmount,
            MOCK_FROM_AMOUNT_SWAP,
            "Test Case 4 Failed: Min amount should be from the first swapData item's fromAmount"
        );
        assertEq(result.destinationChainId, MOCK_DEST_CHAIN_ID, "Test Case 4 Failed: Destination chain ID mismatch");
    }

    // -------------------------------------------------------------------------
    // Tests for validateLifiInfos
    // -------------------------------------------------------------------------

    // Helper addresses and constants for validateLifiInfos tests
    address constant TOKEN_A = address(0xAAbbCCDdeEFf00112233445566778899aABBcCDd);
    address constant TOKEN_B = address(0xbbccDDEEaABBCCdDEEfF00112233445566778899);
    uint256 constant CURRENT_CHAIN_ID = 1; 
    uint256 constant OTHER_CHAIN_ID = 42;

    AnypayLifiInfo[] internal _inferredInfos;
    AnypayLifiInfo[] internal _attestedInfos;

    /**
     * @notice Wrapper to test the internal AnypayLifiInterpreter.validateLifiInfos function.
     * @dev This function explicitly uses the imported AnypayLifiInfo struct.
     */
    function validateLifiInfosWrapper(
        AnypayLifiInfo[] memory inferredLifiInfos,
        AnypayLifiInfo[] memory attestedLifiInfos
    ) public view {
        AnypayLifiInterpreter.validateLifiInfos(inferredLifiInfos, attestedLifiInfos);
    }

    function _setUpValidateLifiInfosTest() internal {
        vm.chainId(CURRENT_CHAIN_ID); 
    }

    function test_ValidateLifiInfos_EmptyArrays() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayLifiInfo[](0);
        _attestedInfos = new AnypayLifiInfo[](0);

        validateLifiInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateLifiInfos_MismatchedLengths_Reverts() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayLifiInfo[](1);
        _inferredInfos[0] = AnypayLifiInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);
        _attestedInfos = new AnypayLifiInfo[](0);

        vm.expectRevert(AnypayLifiInterpreter.MismatchedLifiInfoLengths.selector);
        validateLifiInfosWrapper(_inferredInfos, _attestedInfos);
    }
 
    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateLifiInfos_InferredZeroMinAmount_Reverts() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayLifiInfo[](1);
        _inferredInfos[0] = AnypayLifiInfo(TOKEN_A, 0, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Zero min amount
        _attestedInfos = new AnypayLifiInfo[](1);
        _attestedInfos[0] = AnypayLifiInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);

        vm.expectRevert(AnypayLifiInterpreter.InvalidInferredMinAmount.selector);
        validateLifiInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function test_ValidateLifiInfos_Valid_SingleMatch_CurrentChain() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayLifiInfo[](1);
        _inferredInfos[0] = AnypayLifiInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);
        _attestedInfos = new AnypayLifiInfo[](1);
        _attestedInfos[0] = AnypayLifiInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);

        validateLifiInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }
    
    function test_ValidateLifiInfos_Valid_SingleMatch_InferredAmountHigher() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayLifiInfo[](1);
        _inferredInfos[0] = AnypayLifiInfo(TOKEN_A, 200, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Higher inferred
        _attestedInfos = new AnypayLifiInfo[](1);
        _attestedInfos[0] = AnypayLifiInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);

        validateLifiInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateLifiInfos_NoMatchingInferred_CurrentChain_Reverts() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayLifiInfo[](1);
        _inferredInfos[0] = AnypayLifiInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);
        _attestedInfos = new AnypayLifiInfo[](1);
        // Attested info has different token, no match for TOKEN_B
        _attestedInfos[0] = AnypayLifiInfo(TOKEN_B, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); 

        vm.expectRevert(
            abi.encodeWithSelector(
                AnypayLifiInterpreter.NoMatchingInferredInfoFound.selector,
                CURRENT_CHAIN_ID,
                MOCK_DEST_CHAIN_ID,
                TOKEN_B
            )
        );
        validateLifiInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateLifiInfos_InferredMinAmountTooLow_CurrentChain_Reverts() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayLifiInfo[](1);
        _inferredInfos[0] = AnypayLifiInfo(TOKEN_A, 50, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Inferred amount too low
        _attestedInfos = new AnypayLifiInfo[](1);
        _attestedInfos[0] = AnypayLifiInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);

        vm.expectRevert(
            abi.encodeWithSelector(
                AnypayLifiInterpreter.InferredMinAmountTooLow.selector,
                50,
                100
            )
        );
        validateLifiInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function test_ValidateLifiInfos_AttestedDifferentOriginChain_SkipsValidation() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayLifiInfo[](1);
        _inferredInfos[0] = AnypayLifiInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Valid inferred
        _attestedInfos = new AnypayLifiInfo[](1);
        // Attested is for a different origin chain, so it should be skipped
        _attestedInfos[0] = AnypayLifiInfo(TOKEN_A, 50, OTHER_CHAIN_ID, MOCK_DEST_CHAIN_ID); 

        validateLifiInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    function test_ValidateLifiInfos_MultipleEntries_AllMatch() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayLifiInfo[](2);
        _inferredInfos[0] = AnypayLifiInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);
        _inferredInfos[1] = AnypayLifiInfo(TOKEN_B, 200, CURRENT_CHAIN_ID, OTHER_CHAIN_ID);
        
        _attestedInfos = new AnypayLifiInfo[](2);
        _attestedInfos[0] = AnypayLifiInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);
        _attestedInfos[1] = AnypayLifiInfo(TOKEN_B, 150, CURRENT_CHAIN_ID, OTHER_CHAIN_ID);

        validateLifiInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }
    
    function test_ValidateLifiInfos_MultipleEntries_OneAttestedOtherChain_SkipsAndMatches() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayLifiInfo[](2);
        _inferredInfos[0] = AnypayLifiInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);
        _inferredInfos[1] = AnypayLifiInfo(TOKEN_B, 200, CURRENT_CHAIN_ID, OTHER_CHAIN_ID); // This matches attested[1]

        _attestedInfos = new AnypayLifiInfo[](2);
        _attestedInfos[0] = AnypayLifiInfo(TOKEN_A, 100, OTHER_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Skipped
        _attestedInfos[1] = AnypayLifiInfo(TOKEN_B, 150, CURRENT_CHAIN_ID, OTHER_CHAIN_ID); // Matched

        validateLifiInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateLifiInfos_MultipleEntries_NoMatchForOneCurrentChain_Reverts() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayLifiInfo[](2); // Adjusted length to 2
        _inferredInfos[0] = AnypayLifiInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Matches attested[0]
        _inferredInfos[1] = AnypayLifiInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Does not match attested[1]'s TOKEN_B or OTHER_CHAIN_ID

        _attestedInfos = new AnypayLifiInfo[](2); // Adjusted length to 2
        _attestedInfos[0] = AnypayLifiInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Matches inferred[0]
        _attestedInfos[1] = AnypayLifiInfo(TOKEN_B, 150, CURRENT_CHAIN_ID, OTHER_CHAIN_ID);    // Expect NoMatchingInferredInfoFound for this

        vm.expectRevert(
            abi.encodeWithSelector(
                AnypayLifiInterpreter.NoMatchingInferredInfoFound.selector,
                CURRENT_CHAIN_ID,
                OTHER_CHAIN_ID,
                TOKEN_B
            )
        );
        validateLifiInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateLifiInfos_MultipleEntries_Uniqueness_RevertsIfInferredUsedTwice() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayLifiInfo[](2); // Adjusted length to 2
        _inferredInfos[0] = AnypayLifiInfo(TOKEN_A, 200, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Will be used by attested[0]
        _inferredInfos[1] = AnypayLifiInfo(TOKEN_B, 300, CURRENT_CHAIN_ID, OTHER_CHAIN_ID);   // Decoy, different token

        _attestedInfos = new AnypayLifiInfo[](2); // Adjusted length to 2
        _attestedInfos[0] = AnypayLifiInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Matches and uses inferred[0]
        _attestedInfos[1] = AnypayLifiInfo(TOKEN_A, 150, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Tries to match inferred[0] (used) or inferred[1] (wrong token)

        vm.expectRevert(
            abi.encodeWithSelector(
                AnypayLifiInterpreter.NoMatchingInferredInfoFound.selector,
                CURRENT_CHAIN_ID,
                MOCK_DEST_CHAIN_ID, // destinationChainId for attestedInfos[1]
                TOKEN_A // originToken for attestedInfos[1]
            )
        );
        // The second attestedInfo (TOKEN_A, 150) will fail to find an unused match.
        validateLifiInfosWrapper(_inferredInfos, _attestedInfos);
    }
}

