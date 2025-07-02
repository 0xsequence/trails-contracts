// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {AnypayRelayInfo} from "@/interfaces/AnypayRelay.sol";
import {AnypayRelayDecoder} from "@/libraries/AnypayRelayDecoder.sol";
import {AnypayRelayValidator} from "@/libraries/AnypayRelayValidator.sol";
import {AnypayExecutionInfo} from "@/interfaces/AnypayExecutionInfo.sol";

contract AnypayRelayValidatorTest is Test {
    AnypayRelayInfo internal baseAttestedInfo;
    AnypayRelayDecoder.DecodedRelayData internal baseInferredInfo;

    uint256 internal constant RELAY_SOLVER_PK = 0x1234;
    address internal RELAY_SOLVER;
    uint256 internal constant OTHER_USER_PK = 0x5678;
    address internal OTHER_USER;

    address constant NON_EVM_ADDRESS = 0x1111111111111111111111111111111111111111;

    bytes32 constant MOCK_REQUEST_ID = keccak256("request_id");
    address constant MOCK_TOKEN = address(0x1);
    address constant MOCK_RECEIVER = address(0x2);
    uint256 constant MOCK_AMOUNT = 100 ether;

    address internal MOCK_TARGET;

    function setUp() public {
        RELAY_SOLVER = vm.addr(RELAY_SOLVER_PK);
        OTHER_USER = vm.addr(OTHER_USER_PK);

        vm.label(RELAY_SOLVER, "Relay Solver");
        vm.label(OTHER_USER, "Other User");

        baseInferredInfo = AnypayRelayDecoder.DecodedRelayData({
            requestId: MOCK_REQUEST_ID,
            token: MOCK_TOKEN,
            amount: MOCK_AMOUNT,
            receiver: MOCK_RECEIVER
        });

        baseAttestedInfo = AnypayRelayInfo({
            requestId: MOCK_REQUEST_ID,
            signature: new bytes(0),
            nonEVMReceiver: bytes32(0),
            receivingAssetId: bytes32(0),
            sendingAssetId: MOCK_TOKEN,
            receiver: MOCK_RECEIVER,
            destinationChainId: 1,
            minAmount: MOCK_AMOUNT,
            target: address(this)
        });
        MOCK_TARGET = address(this);
    }

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
        AnypayRelayValidator.validateRelayInfos(inferredRelayInfos, attestedRelayInfos);
    }

    function test_ValidateRelayInfos_EmptyArrays() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](0);
        _attestedInfos = new AnypayExecutionInfo[](0);

        validateRelayInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_MismatchedLengths_Reverts() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] = AnypayRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 100,
            receiver: MOCK_TARGET
        });
        _attestedInfos = new AnypayExecutionInfo[](0);

        vm.expectRevert(AnypayRelayValidator.MismatchedRelayInfoLengths.selector);
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_InferredZeroMinAmount_Reverts() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] = AnypayRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 0,
            receiver: MOCK_TARGET
        });
        _attestedInfos = new AnypayExecutionInfo[](1);
        _attestedInfos[0] = AnypayExecutionInfo({
            originToken: TOKEN_A,
            amount: 100,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });

        vm.expectRevert(AnypayRelayValidator.InvalidInferredMinAmount.selector);
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function test_ValidateRelayInfos_Valid_SingleMatch() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] = AnypayRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 100,
            receiver: MOCK_TARGET
        });
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
        _inferredInfos[0] = AnypayRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 200,
            receiver: MOCK_TARGET
        });
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
        _inferredInfos[0] = AnypayRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 100,
            receiver: MOCK_TARGET
        });
        _attestedInfos = new AnypayExecutionInfo[](1);
        _attestedInfos[0] = AnypayExecutionInfo({
            originToken: TOKEN_B,
            amount: 100,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                AnypayRelayValidator.NoMatchingInferredInfoFound.selector, MOCK_DEST_CHAIN_ID, TOKEN_B
            )
        );
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_InferredAmountTooHigh_Reverts() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] = AnypayRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 100,
            receiver: MOCK_TARGET
        });
        _attestedInfos = new AnypayExecutionInfo[](1);
        _attestedInfos[0] = AnypayExecutionInfo({
            originToken: TOKEN_A,
            amount: 50,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });

        vm.expectRevert(abi.encodeWithSelector(AnypayRelayValidator.InferredAmountTooHigh.selector, 100, 50));
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function test_ValidateRelayInfos_MultipleEntries_AllMatch() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](2);
        _inferredInfos[0] = AnypayRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 200,
            receiver: MOCK_TARGET
        });
        _inferredInfos[1] = AnypayRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_B,
            amount: 100,
            receiver: MOCK_TARGET
        });

        _attestedInfos = new AnypayExecutionInfo[](2);
        _attestedInfos[0] = AnypayExecutionInfo({
            originToken: TOKEN_A,
            amount: 200,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });
        _attestedInfos[1] = AnypayExecutionInfo({
            originToken: TOKEN_B,
            amount: 100,
            originChainId: block.chainid,
            destinationChainId: OTHER_CHAIN_ID
        });

        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_MultipleEntries_NoMatchForOne_Reverts() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](2);
        _inferredInfos[0] = AnypayRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 100,
            receiver: MOCK_TARGET
        });
        _inferredInfos[1] = AnypayRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 100,
            receiver: MOCK_TARGET
        });

        _attestedInfos = new AnypayExecutionInfo[](2);
        _attestedInfos[0] = AnypayExecutionInfo({
            originToken: TOKEN_A,
            amount: 100,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });
        _attestedInfos[1] = AnypayExecutionInfo({
            originToken: TOKEN_B,
            amount: 150,
            originChainId: block.chainid,
            destinationChainId: OTHER_CHAIN_ID
        });

        vm.expectRevert(
            abi.encodeWithSelector(AnypayRelayValidator.NoMatchingInferredInfoFound.selector, OTHER_CHAIN_ID, TOKEN_B)
        );
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_MultipleEntries_Uniqueness_RevertsIfInferredUsedTwice() public {
        _inferredInfos = new AnypayRelayDecoder.DecodedRelayData[](2);
        _inferredInfos[0] = AnypayRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 300,
            receiver: MOCK_TARGET
        });
        _inferredInfos[1] = AnypayRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_B,
            amount: 300,
            receiver: MOCK_TARGET
        });

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
                AnypayRelayValidator.NoMatchingInferredInfoFound.selector,
                MOCK_DEST_CHAIN_ID, // destinationChainId for attestedInfos[1]
                TOKEN_A // sendingAssetId for attestedInfos[1]
            )
        );
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function _signRelayInfo(AnypayRelayInfo memory info, uint256 privateKey) internal view returns (bytes memory) {
        bytes32 message = keccak256(
            abi.encodePacked(
                info.requestId,
                block.chainid,
                bytes32(uint256(uint160(info.target))),
                bytes32(uint256(uint160(info.sendingAssetId))),
                info.destinationChainId,
                info.receiver == NON_EVM_ADDRESS ? info.nonEVMReceiver : bytes32(uint256(uint160(info.receiver))),
                info.receivingAssetId,
                info.minAmount
            )
        );
        bytes32 digest = ECDSA.toEthSignedMessageHash(message);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
