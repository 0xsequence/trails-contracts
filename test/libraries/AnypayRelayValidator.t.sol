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

    address constant NON_EVM_RECEIVER = 0x0000000000000000000000000000000000000000;

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
                info.receiver == NON_EVM_RECEIVER
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
}
