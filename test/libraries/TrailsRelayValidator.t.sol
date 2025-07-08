// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {TrailsRelayInfo} from "@/interfaces/TrailsRelay.sol";
import {TrailsRelayDecoder} from "@/libraries/TrailsRelayDecoder.sol";
import {TrailsRelayValidator} from "@/libraries/TrailsRelayValidator.sol";
import {TrailsExecutionInfo} from "@/interfaces/TrailsExecutionInfo.sol";

contract TrailsRelayValidatorTest is Test {
    TrailsRelayInfo internal baseAttestedInfo;
    TrailsRelayDecoder.DecodedRelayData internal baseInferredInfo;

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

        baseInferredInfo = TrailsRelayDecoder.DecodedRelayData({
            requestId: MOCK_REQUEST_ID,
            token: MOCK_TOKEN,
            amount: MOCK_AMOUNT,
            receiver: MOCK_RECEIVER
        });

        baseAttestedInfo = TrailsRelayInfo({
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

    TrailsRelayDecoder.DecodedRelayData[] internal _inferredInfos;
    TrailsExecutionInfo[] internal _attestedInfos;

    function validateRelayInfosWrapper(
        TrailsRelayDecoder.DecodedRelayData[] memory inferredRelayInfos,
        TrailsExecutionInfo[] memory attestedRelayInfos
    ) public view {
        TrailsRelayValidator.validateRelayInfos(inferredRelayInfos, attestedRelayInfos);
    }

    function test_ValidateRelayInfos_EmptyArrays() public {
        _inferredInfos = new TrailsRelayDecoder.DecodedRelayData[](0);
        _attestedInfos = new TrailsExecutionInfo[](0);

        validateRelayInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_InferredZeroMinAmount_Reverts() public {
        _inferredInfos = new TrailsRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] = TrailsRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 0,
            receiver: MOCK_TARGET
        });
        _attestedInfos = new TrailsExecutionInfo[](1);
        _attestedInfos[0] = TrailsExecutionInfo({
            originToken: TOKEN_A,
            amount: 100,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });

        vm.expectRevert(TrailsRelayValidator.InvalidInferredMinAmount.selector);
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function test_ValidateRelayInfos_Valid_SingleMatch() public {
        _inferredInfos = new TrailsRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] = TrailsRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 100,
            receiver: MOCK_TARGET
        });
        _attestedInfos = new TrailsExecutionInfo[](1);
        _attestedInfos[0] = TrailsExecutionInfo({
            originToken: TOKEN_A,
            amount: 100,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });

        validateRelayInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    function test_ValidateRelayInfos_Valid_SingleMatch_InferredAmountHigher() public {
        _inferredInfos = new TrailsRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] = TrailsRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 200,
            receiver: MOCK_TARGET
        });
        _attestedInfos = new TrailsExecutionInfo[](1);
        _attestedInfos[0] = TrailsExecutionInfo({
            originToken: TOKEN_A,
            amount: 200,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });

        validateRelayInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_NoMatchingInferred_Reverts() public {
        _inferredInfos = new TrailsRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] = TrailsRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 100,
            receiver: MOCK_TARGET
        });
        _attestedInfos = new TrailsExecutionInfo[](1);
        _attestedInfos[0] = TrailsExecutionInfo({
            originToken: TOKEN_B,
            amount: 100,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                TrailsRelayValidator.NoMatchingInferredInfoFound.selector, MOCK_DEST_CHAIN_ID, TOKEN_B
            )
        );
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_InferredAmountTooHigh_Reverts() public {
        _inferredInfos = new TrailsRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] = TrailsRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 100,
            receiver: MOCK_TARGET
        });
        _attestedInfos = new TrailsExecutionInfo[](1);
        _attestedInfos[0] = TrailsExecutionInfo({
            originToken: TOKEN_A,
            amount: 50,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });

        vm.expectRevert(abi.encodeWithSelector(TrailsRelayValidator.InferredAmountTooHigh.selector, 100, 50));
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function test_ValidateRelayInfos_InferredAmountLower_ShouldPass() public {
        _inferredInfos = new TrailsRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] = TrailsRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 50,
            receiver: MOCK_TARGET
        });
        _attestedInfos = new TrailsExecutionInfo[](1);
        _attestedInfos[0] = TrailsExecutionInfo({
            originToken: TOKEN_A,
            amount: 100,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });

        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function test_ValidateRelayInfos_MulticallRelay_AmountLower_ShouldPass() public {
        _inferredInfos = new TrailsRelayDecoder.DecodedRelayData[](1);
        _inferredInfos[0] = TrailsRelayDecoder.DecodedRelayData({
            requestId: bytes32(type(uint256).max),
            token: address(0),
            amount: 727419845055165468,
            receiver: MOCK_TARGET
        });
        _attestedInfos = new TrailsExecutionInfo[](1);
        _attestedInfos[0] = TrailsExecutionInfo({
            originToken: address(0),
            amount: 2405267880456802874,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });

        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function test_ValidateRelayInfos_MultipleEntries_AllMatch() public {
        _inferredInfos = new TrailsRelayDecoder.DecodedRelayData[](2);
        _inferredInfos[0] = TrailsRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 200,
            receiver: MOCK_TARGET
        });
        _inferredInfos[1] = TrailsRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_B,
            amount: 100,
            receiver: MOCK_TARGET
        });

        _attestedInfos = new TrailsExecutionInfo[](2);
        _attestedInfos[0] = TrailsExecutionInfo({
            originToken: TOKEN_A,
            amount: 200,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });
        _attestedInfos[1] = TrailsExecutionInfo({
            originToken: TOKEN_B,
            amount: 100,
            originChainId: block.chainid,
            destinationChainId: OTHER_CHAIN_ID
        });

        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_MultipleEntries_NoMatchForOne_Reverts() public {
        _inferredInfos = new TrailsRelayDecoder.DecodedRelayData[](2);
        _inferredInfos[0] = TrailsRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 100,
            receiver: MOCK_TARGET
        });
        _inferredInfos[1] = TrailsRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 100,
            receiver: MOCK_TARGET
        });

        _attestedInfos = new TrailsExecutionInfo[](2);
        _attestedInfos[0] = TrailsExecutionInfo({
            originToken: TOKEN_A,
            amount: 100,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });
        _attestedInfos[1] = TrailsExecutionInfo({
            originToken: TOKEN_B,
            amount: 150,
            originChainId: block.chainid,
            destinationChainId: OTHER_CHAIN_ID
        });

        vm.expectRevert(
            abi.encodeWithSelector(TrailsRelayValidator.NoMatchingInferredInfoFound.selector, OTHER_CHAIN_ID, TOKEN_B)
        );
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_MultipleEntries_Uniqueness_RevertsIfInferredUsedTwice() public {
        _inferredInfos = new TrailsRelayDecoder.DecodedRelayData[](2);
        _inferredInfos[0] = TrailsRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_A,
            amount: 300,
            receiver: MOCK_TARGET
        });
        _inferredInfos[1] = TrailsRelayDecoder.DecodedRelayData({
            requestId: bytes32(0),
            token: TOKEN_B,
            amount: 300,
            receiver: MOCK_TARGET
        });

        _attestedInfos = new TrailsExecutionInfo[](2);
        _attestedInfos[0] = TrailsExecutionInfo({
            originToken: TOKEN_A,
            amount: 300,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });
        _attestedInfos[1] = TrailsExecutionInfo({
            originToken: TOKEN_A,
            amount: 300,
            originChainId: block.chainid,
            destinationChainId: MOCK_DEST_CHAIN_ID
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                TrailsRelayValidator.NoMatchingInferredInfoFound.selector,
                MOCK_DEST_CHAIN_ID, // destinationChainId for attestedInfos[1]
                TOKEN_A // sendingAssetId for attestedInfos[1]
            )
        );
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function _signRelayInfo(TrailsRelayInfo memory info, uint256 privateKey) internal view returns (bytes memory) {
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
