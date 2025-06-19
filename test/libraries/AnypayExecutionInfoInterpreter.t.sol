// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";
import {AnypayExecutionInfoInterpreter, AnypayExecutionInfo} from "@/libraries/AnypayExecutionInfoInterpreter.sol";

contract AnypayExecutionInfoInterpreterTest is Test {
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

    // Helper addresses and constants for validateLifiInfos tests
    address constant TOKEN_A = address(0xAAbbCCDdeEFf00112233445566778899aABBcCDd);
    address constant TOKEN_B = address(0xbbccDDEEaABBCCdDEEfF00112233445566778899);
    uint256 constant CURRENT_CHAIN_ID = 1;
    uint256 constant OTHER_CHAIN_ID = 42;

    AnypayExecutionInfo[] internal _inferredInfos;
    AnypayExecutionInfo[] internal _attestedInfos;

    /**
     * @notice Wrapper to test the internal AnypayLiFiInterpreter.validateLifiInfos function.
     * @dev This function explicitly uses the imported AnypayExecutionInfo struct.
     */
    function validateLifiInfosWrapper(
        AnypayExecutionInfo[] memory inferredLifiInfos,
        AnypayExecutionInfo[] memory attestedLifiInfos
    ) public view {
        AnypayExecutionInfoInterpreter.validateExecutionInfos(inferredLifiInfos, attestedLifiInfos);
    }

    function _setUpValidateLifiInfosTest() internal {
        vm.chainId(CURRENT_CHAIN_ID);
    }

    function test_ValidateExecutionInfos_EmptyArrays() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayExecutionInfo[](0);
        _attestedInfos = new AnypayExecutionInfo[](0);

        validateLifiInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateExecutionInfos_MismatchedLengths_Reverts() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayExecutionInfo[](1);
        _inferredInfos[0] = AnypayExecutionInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);
        _attestedInfos = new AnypayExecutionInfo[](0);

        vm.expectRevert(AnypayExecutionInfoInterpreter.MismatchedExecutionInfoLengths.selector);
        validateLifiInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateExecutionInfos_InferredZeroMinAmount_Reverts() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayExecutionInfo[](1);
        _inferredInfos[0] = AnypayExecutionInfo(TOKEN_A, 0, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Zero min amount
        _attestedInfos = new AnypayExecutionInfo[](1);
        _attestedInfos[0] = AnypayExecutionInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);

        vm.expectRevert(AnypayExecutionInfoInterpreter.InvalidInferredMinAmount.selector);
        validateLifiInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function test_ValidateExecutionInfos_Valid_SingleMatch_CurrentChain() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayExecutionInfo[](1);
        _inferredInfos[0] = AnypayExecutionInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);
        _attestedInfos = new AnypayExecutionInfo[](1);
        _attestedInfos[0] = AnypayExecutionInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);

        validateLifiInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    function test_ValidateExecutionInfos_Valid_SingleMatch_InferredAmountHigher() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayExecutionInfo[](1);
        _inferredInfos[0] = AnypayExecutionInfo(TOKEN_A, 200, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Higher inferred
        _attestedInfos = new AnypayExecutionInfo[](1);
        _attestedInfos[0] = AnypayExecutionInfo(TOKEN_A, 200, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);

        validateLifiInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateExecutionInfos_NoMatchingInferred_CurrentChain_Reverts() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayExecutionInfo[](1);
        _inferredInfos[0] = AnypayExecutionInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);
        _attestedInfos = new AnypayExecutionInfo[](1);
        // Attested info has different token, no match for TOKEN_B
        _attestedInfos[0] = AnypayExecutionInfo(TOKEN_B, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);

        vm.expectRevert(
            abi.encodeWithSelector(
                AnypayExecutionInfoInterpreter.NoMatchingInferredInfoFound.selector,
                CURRENT_CHAIN_ID,
                MOCK_DEST_CHAIN_ID,
                TOKEN_B
            )
        );
        validateLifiInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateExecutionInfos_InferredAmountTooHigh_CurrentChain_Reverts() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayExecutionInfo[](1);
        _inferredInfos[0] = AnypayExecutionInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);
        _attestedInfos = new AnypayExecutionInfo[](1);
        _attestedInfos[0] = AnypayExecutionInfo(TOKEN_A, 50, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);

        vm.expectRevert(abi.encodeWithSelector(AnypayExecutionInfoInterpreter.InferredAmountTooHigh.selector, 100, 50));
        validateLifiInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function test_ValidateExecutionInfos_AttestedDifferentOriginChain_SkipsValidation() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayExecutionInfo[](1);
        _inferredInfos[0] = AnypayExecutionInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Valid inferred
        _attestedInfos = new AnypayExecutionInfo[](1);
        // Attested is for a different origin chain, so it should be skipped
        _attestedInfos[0] = AnypayExecutionInfo(TOKEN_A, 50, OTHER_CHAIN_ID, MOCK_DEST_CHAIN_ID);

        validateLifiInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    function test_ValidateExecutionInfos_MultipleEntries_AllMatch() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayExecutionInfo[](2);
        _inferredInfos[0] = AnypayExecutionInfo(TOKEN_A, 200, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);
        _inferredInfos[1] = AnypayExecutionInfo(TOKEN_B, 100, CURRENT_CHAIN_ID, OTHER_CHAIN_ID);

        _attestedInfos = new AnypayExecutionInfo[](2);
        _attestedInfos[0] = AnypayExecutionInfo(TOKEN_A, 200, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);
        _attestedInfos[1] = AnypayExecutionInfo(TOKEN_B, 100, CURRENT_CHAIN_ID, OTHER_CHAIN_ID);

        validateLifiInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function test_ValidateExecutionInfos_MultipleEntries_OneAttestedOtherChain_SkipsAndMatches() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayExecutionInfo[](2);
        _inferredInfos[0] = AnypayExecutionInfo(TOKEN_A, 200, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID);
        _inferredInfos[1] = AnypayExecutionInfo(TOKEN_B, 100, CURRENT_CHAIN_ID, OTHER_CHAIN_ID); // This matches attested[1]

        _attestedInfos = new AnypayExecutionInfo[](2);
        _attestedInfos[0] = AnypayExecutionInfo(TOKEN_A, 300, OTHER_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Skipped
        _attestedInfos[1] = AnypayExecutionInfo(TOKEN_B, 150, CURRENT_CHAIN_ID, OTHER_CHAIN_ID); // Matched

        validateLifiInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateExecutionInfos_MultipleEntries_NoMatchForOneCurrentChain_Reverts() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayExecutionInfo[](2); // Adjusted length to 2
        _inferredInfos[0] = AnypayExecutionInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Matches attested[0]
        _inferredInfos[1] = AnypayExecutionInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Does not match attested[1]'s TOKEN_B or OTHER_CHAIN_ID

        _attestedInfos = new AnypayExecutionInfo[](2); // Adjusted length to 2
        _attestedInfos[0] = AnypayExecutionInfo(TOKEN_A, 100, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Matches inferred[0]
        _attestedInfos[1] = AnypayExecutionInfo(TOKEN_B, 150, CURRENT_CHAIN_ID, OTHER_CHAIN_ID); // Expect NoMatchingInferredInfoFound for this

        vm.expectRevert(
            abi.encodeWithSelector(
                AnypayExecutionInfoInterpreter.NoMatchingInferredInfoFound.selector, CURRENT_CHAIN_ID, OTHER_CHAIN_ID, TOKEN_B
            )
        );
        validateLifiInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateExecutionInfos_MultipleEntries_Uniqueness_RevertsIfInferredUsedTwice() public {
        _setUpValidateLifiInfosTest();
        _inferredInfos = new AnypayExecutionInfo[](2); // Adjusted length to 2
        _inferredInfos[0] = AnypayExecutionInfo(TOKEN_A, 200, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Will be used by attested[0]
        _inferredInfos[1] = AnypayExecutionInfo(TOKEN_B, 300, CURRENT_CHAIN_ID, OTHER_CHAIN_ID); // Decoy, different token

        _attestedInfos = new AnypayExecutionInfo[](2); // Adjusted length to 2
        _attestedInfos[0] = AnypayExecutionInfo(TOKEN_A, 300, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Matches and uses inferred[0]
        _attestedInfos[1] = AnypayExecutionInfo(TOKEN_A, 300, CURRENT_CHAIN_ID, MOCK_DEST_CHAIN_ID); // Tries to match inferred[0] (used) or inferred[1] (wrong token)

        vm.expectRevert(
            abi.encodeWithSelector(
                AnypayExecutionInfoInterpreter.NoMatchingInferredInfoFound.selector,
                CURRENT_CHAIN_ID,
                MOCK_DEST_CHAIN_ID, // destinationChainId for attestedInfos[1]
                TOKEN_A // originToken for attestedInfos[1]
            )
        );
        // The second attestedInfo (TOKEN_A, 150) will fail to find an unused match.
        validateLifiInfosWrapper(_inferredInfos, _attestedInfos);
    }
}
