// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {AnypayRelayInterpreter} from "@/libraries/AnypayRelayInterpreter.sol";
import {AnypayRelayDecoder} from "@/libraries/AnypayRelayDecoder.sol";
import {AnypayExecutionInfo} from "@/interfaces/AnypayExecutionInfo.sol";

contract AnypayRelayInterpreterTest is Test {
    address internal MOCK_TARGET;

    function setUp() public {
        MOCK_TARGET = address(this);
    }

    // -------------------------------------------------------------------------
    // Tests for validateRelayInfos
    // -------------------------------------------------------------------------

    address constant TOKEN_A = address(0xAAbbCCDdeEFf00112233445566778899aABBcCDd);
    address constant TOKEN_B = address(0xbbccDDEEaABBCCdDEEfF00112233445566778899);
    uint256 constant MOCK_DEST_CHAIN_ID = 137;
    uint256 constant OTHER_CHAIN_ID = 42;

    AnypayRelayDecoder.DecodedRelayData[] internal _inferredInfos;
    AnypayExecutionInfo[] internal _attestedInfos;

    function validateRelayInfosWrapper(
        AnypayRelayDecoder.DecodedRelayData[] memory inferredRelayInfos,
        AnypayExecutionInfo[] memory attestedRelayInfos
    ) public view {
        AnypayRelayInterpreter.validateRelayInfos(inferredRelayInfos, attestedRelayInfos);
    }

    function test_ValidateRelayInfos_EmptyArrays() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](0);
        _attestedInfos = new AnypayExecutionInfo[](0);

        validateRelayInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_MismatchedLengths_Reverts() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] =
            AnypayRelayDecoder.DecodedRelayData({requestId: bytes32(0), token: TOKEN_A, amount: 100, receiver: MOCK_TARGET});
        _attestedInfos = new AnypayExecutionInfo[](0);

        vm.expectRevert(AnypayRelayInterpreter.MismatchedRelayInfoLengths.selector);
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_InferredZeroMinAmount_Reverts() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] =
            AnypayRelayDecoder.DecodedRelayData({requestId: bytes32(0), token: TOKEN_A, amount: 0, receiver: MOCK_TARGET});
        _attestedInfos = new AnypayExecutionInfo[](1);
        _attestedInfos[0] = AnypayExecutionInfo({
            originToken: TOKEN_A,
            amount: 100,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });

        vm.expectRevert(AnypayRelayInterpreter.InvalidInferredMinAmount.selector);
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function test_ValidateRelayInfos_Valid_SingleMatch() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] =
            AnypayRelayDecoder.DecodedRelayData({requestId: bytes32(0), token: TOKEN_A, amount: 100, receiver: MOCK_TARGET});
        _attestedInfos = new AnypayExecutionInfo[](1);
        _attestedInfos[0] = AnypayExecutionInfo({
            originToken: TOKEN_A,
            amount: 100,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });

        validateRelayInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    function test_ValidateRelayInfos_Valid_SingleMatch_InferredAmountHigher() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] =
            AnypayRelayDecoder.DecodedRelayData({requestId: bytes32(0), token: TOKEN_A, amount: 200, receiver: MOCK_TARGET});
        _attestedInfos = new AnypayExecutionInfo[](1);
        _attestedInfos[0] = AnypayExecutionInfo({
            originToken: TOKEN_A,
            amount: 200,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });

        validateRelayInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_NoMatchingInferred_Reverts() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] =
            AnypayRelayDecoder.DecodedRelayData({requestId: bytes32(0), token: TOKEN_A, amount: 100, receiver: MOCK_TARGET});
        _attestedInfos = new AnypayExecutionInfo[](1);
        _attestedInfos[0] = AnypayExecutionInfo({
            originToken: TOKEN_B,
            amount: 100,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                AnypayRelayInterpreter.NoMatchingInferredInfoFound.selector, MOCK_DEST_CHAIN_ID, TOKEN_B
            )
        );
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_InferredAmountTooHigh_Reverts() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] =
            AnypayRelayDecoder.DecodedRelayData({requestId: bytes32(0), token: TOKEN_A, amount: 100, receiver: MOCK_TARGET});
        _attestedInfos = new AnypayExecutionInfo[](1);
        _attestedInfos[0] = AnypayExecutionInfo(
            {originToken: TOKEN_A, amount: 50, originChainId: block.chainid, destinationChainId: MOCK_DEST_CHAIN_ID}
        );

        vm.expectRevert(abi.encodeWithSelector(AnypayRelayInterpreter.InferredAmountTooHigh.selector, 100, 50));
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function test_ValidateRelayInfos_MultipleEntries_AllMatch() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](2);
        _inferredInfos[0] =
            AnypayRelayDecoder.DecodedRelayData({requestId: bytes32(0), token: TOKEN_A, amount: 200, receiver: MOCK_TARGET});
        _inferredInfos[1] =
            AnypayRelayDecoder.DecodedRelayData({requestId: bytes32(0), token: TOKEN_B, amount: 100, receiver: MOCK_TARGET});

        _attestedInfos = new AnypayExecutionInfo[](2);
        _attestedInfos[0] = AnypayExecutionInfo({
            originToken: TOKEN_A,
            amount: 200,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });
        _attestedInfos[1] =
            AnypayExecutionInfo({originToken: TOKEN_B, amount: 100, originChainId: block.chainid, destinationChainId: OTHER_CHAIN_ID});

        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_MultipleEntries_NoMatchForOne_Reverts() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](2);
        _inferredInfos[0] =
            AnypayRelayDecoder.DecodedRelayData({requestId: bytes32(0), token: TOKEN_A, amount: 100, receiver: MOCK_TARGET});
        _inferredInfos[1] =
            AnypayRelayDecoder.DecodedRelayData({requestId: bytes32(0), token: TOKEN_A, amount: 100, receiver: MOCK_TARGET});

        _attestedInfos = new AnypayExecutionInfo[](2);
        _attestedInfos[0] = AnypayExecutionInfo({
            originToken: TOKEN_A,
            amount: 100,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });
        _attestedInfos[1] = AnypayExecutionInfo(
            {originToken: TOKEN_B, amount: 150, originChainId: block.chainid, destinationChainId: OTHER_CHAIN_ID}
        );

        vm.expectRevert(
            abi.encodeWithSelector(AnypayRelayInterpreter.NoMatchingInferredInfoFound.selector, OTHER_CHAIN_ID, TOKEN_B)
        );
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_MultipleEntries_Uniqueness_RevertsIfInferredUsedTwice() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](2);
        _inferredInfos[0] =
            AnypayRelayDecoder.DecodedRelayData({requestId: bytes32(0), token: TOKEN_A, amount: 300, receiver: MOCK_TARGET});
        _inferredInfos[1] =
            AnypayRelayDecoder.DecodedRelayData({requestId: bytes32(0), token: TOKEN_B, amount: 300, receiver: MOCK_TARGET});

        _attestedInfos = new AnypayExecutionInfo[](2);
        _attestedInfos[0] = AnypayExecutionInfo({
            originToken: TOKEN_A,
            amount: 300,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });
        _attestedInfos[1] = AnypayExecutionInfo({
            originToken: TOKEN_A,
            amount: 300,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                AnypayRelayInterpreter.NoMatchingInferredInfoFound.selector,
                MOCK_DEST_CHAIN_ID, // destinationChainId for attestedInfos[1]
                TOKEN_A // sendingAssetId for attestedInfos[1]
            )
        );
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }
}
