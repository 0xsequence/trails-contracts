// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {AnypayRelayInfo} from "@/interfaces/AnypayRelay.sol";
import {AnypayRelayDecoder} from "@/libraries/AnypayRelayDecoder.sol";
import {AnypayRelayValidator} from "@/libraries/AnypayRelayValidator.sol";

contract AnypayRelayValidatorTest is Test {
    AnypayRelayInfo internal baseAttestedInfo;
    AnypayRelayDecoder.DecodedRelayData internal baseInferredInfo;

    uint256 internal constant RELAY_SOLVER_PK = 0x1234;
    address internal RELAY_SOLVER;
    uint256 internal constant OTHER_USER_PK = 0x5678;
    address internal OTHER_USER;

    bytes32 constant MOCK_REQUEST_ID = keccak256("request_id");
    address constant MOCK_TOKEN = address(0x1);
    address constant MOCK_RECEIVER = address(0x2);
    uint256 constant MOCK_AMOUNT = 100 ether;

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
    }

    function _signRelayInfo(AnypayRelayInfo memory info, uint256 privateKey) internal view returns (bytes memory) {
        bytes32 message = keccak256(
            abi.encodePacked(
                info.requestId,
                block.chainid,
                bytes32(uint256(uint160(info.target))),
                bytes32(uint256(uint160(info.sendingAssetId))),
                info.destinationChainId,
                info.receiver == AnypayRelayValidator.NON_EVM_ADDRESS
                    ? info.nonEVMReceiver
                    : bytes32(uint256(uint160(info.receiver))),
                info.receivingAssetId,
                info.minAmount
            )
        );
        bytes32 digest = ECDSA.toEthSignedMessageHash(message);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_ValidateRelayInfo_HappyPath() public view {
        AnypayRelayInfo memory attestedInfo = baseAttestedInfo;
        attestedInfo.signature = _signRelayInfo(attestedInfo, RELAY_SOLVER_PK);
        AnypayRelayValidator.validateRelayInfo(attestedInfo, baseInferredInfo, RELAY_SOLVER);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_Revert_When_RequestIdMismatch() public {
        AnypayRelayInfo memory attestedInfo = baseAttestedInfo;
        attestedInfo.signature = _signRelayInfo(attestedInfo, RELAY_SOLVER_PK);
        AnypayRelayDecoder.DecodedRelayData memory inferredInfo = baseInferredInfo;
        inferredInfo.requestId = keccak256("different_request_id");

        vm.expectRevert(AnypayRelayValidator.InvalidAttestation.selector);
        AnypayRelayValidator.validateRelayInfo(attestedInfo, inferredInfo, RELAY_SOLVER);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_Revert_When_TokenMismatch() public {
        AnypayRelayInfo memory attestedInfo = baseAttestedInfo;
        attestedInfo.signature = _signRelayInfo(attestedInfo, RELAY_SOLVER_PK);
        AnypayRelayDecoder.DecodedRelayData memory inferredInfo = baseInferredInfo;
        inferredInfo.token = address(0x3);

        vm.expectRevert(AnypayRelayValidator.InvalidAttestation.selector);
        AnypayRelayValidator.validateRelayInfo(attestedInfo, inferredInfo, RELAY_SOLVER);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_Revert_When_ReceiverMismatch() public {
        AnypayRelayInfo memory attestedInfo = baseAttestedInfo;
        attestedInfo.signature = _signRelayInfo(attestedInfo, RELAY_SOLVER_PK);
        AnypayRelayDecoder.DecodedRelayData memory inferredInfo = baseInferredInfo;
        inferredInfo.receiver = address(0x4);

        vm.expectRevert(AnypayRelayValidator.InvalidAttestation.selector);
        AnypayRelayValidator.validateRelayInfo(attestedInfo, inferredInfo, RELAY_SOLVER);
    }

    // function test_Revert_When_InvalidSignature() public {
    //     AnypayRelayInfo memory attestedInfo = baseAttestedInfo;
    //     attestedInfo.signature = _signRelayInfo(attestedInfo, OTHER_USER_PK);

    //     vm.expectRevert(AnypayRelayValidator.InvalidAttestation.selector);
    //     AnypayRelayValidator.validateRelayInfo(attestedInfo, baseInferredInfo, RELAY_SOLVER);
    // }

    // function test_Revert_When_SignatureForDifferentPayload() public {
    //     AnypayRelayInfo memory attestedInfo = baseAttestedInfo;
    //     attestedInfo.signature = _signRelayInfo(attestedInfo, RELAY_SOLVER_PK);
    //     attestedInfo.destinationChainId = 2; // Change payload after signing

    //     vm.expectRevert();
    //     AnypayRelayValidator.validateRelayInfo(attestedInfo, baseInferredInfo, RELAY_SOLVER);
    // }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_Revert_When_AmountTooLow() public {
        AnypayRelayInfo memory attestedInfo = baseAttestedInfo;
        attestedInfo.signature = _signRelayInfo(attestedInfo, RELAY_SOLVER_PK);
        AnypayRelayDecoder.DecodedRelayData memory inferredInfo = baseInferredInfo;
        inferredInfo.amount = MOCK_AMOUNT - 1;

        vm.expectRevert(AnypayRelayValidator.InvalidAttestation.selector);
        AnypayRelayValidator.validateRelayInfo(attestedInfo, inferredInfo, RELAY_SOLVER);
    }
}
