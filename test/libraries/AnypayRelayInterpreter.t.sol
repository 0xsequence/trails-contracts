// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {RelayFacet} from "lifi-contracts/Facets/RelayFacet.sol";
import {AnypayRelayInterpreter, AnypayRelayInfo} from "@/libraries/AnypayRelayInterpreter.sol";

contract AnypayRelayInterpreterTest is Test {
    // Mock data for ILiFi.BridgeData
    ILiFi.BridgeData internal mockBridgeData;

    // Mock data for RelayFacet.RelayData
    RelayFacet.RelayData internal mockRelayData;

    // Constants for mock data
    bytes32 constant MOCK_REQUEST_ID = bytes32(uint256(0xABCDEF1234567890));
    bytes32 constant MOCK_NON_EVM_RECEIVER = bytes32(uint256(0x12345));
    bytes32 constant MOCK_RECEIVING_ASSET_ID = bytes32(uint256(0x67890));
    bytes internal MOCK_SIGNATURE = hex"1234";

    uint256 constant MOCK_DEST_CHAIN_ID = 137; // e.g., Polygon
    address constant MOCK_SENDING_ASSET_BRIDGE = address(0x1111111111111111111111111111111111111111);
    uint256 constant MOCK_MIN_AMOUNT_BRIDGE = 1000 * 1e18; // 1000 tokens
    address constant MOCK_RECEIVER = address(0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa);
    address internal MOCK_TARGET;

    function setUp() public {
        MOCK_TARGET = address(this);
        mockBridgeData = ILiFi.BridgeData({
            transactionId: bytes32(0),
            bridge: "TestBridge",
            integrator: "TestIntegrator",
            referrer: address(0x0),
            sendingAssetId: MOCK_SENDING_ASSET_BRIDGE,
            receiver: MOCK_RECEIVER,
            minAmount: MOCK_MIN_AMOUNT_BRIDGE,
            destinationChainId: MOCK_DEST_CHAIN_ID,
            hasSourceSwaps: false,
            hasDestinationCall: false
        });

        mockRelayData = RelayFacet.RelayData({
            requestId: MOCK_REQUEST_ID,
            nonEVMReceiver: MOCK_NON_EVM_RECEIVER,
            receivingAssetId: MOCK_RECEIVING_ASSET_ID,
            signature: MOCK_SIGNATURE
        });
    }

    function test_GetOriginInfo() public {
        AnypayRelayInfo memory result = AnypayRelayInterpreter.getOriginInfo(mockBridgeData, mockRelayData);

        assertEq(result.requestId, MOCK_REQUEST_ID, "Test Case 1 Failed: requestId mismatch");
        assertEq(result.signature, MOCK_SIGNATURE, "Test Case 1 Failed: signature mismatch");
        assertEq(result.nonEVMReceiver, MOCK_NON_EVM_RECEIVER, "Test Case 1 Failed: nonEVMReceiver mismatch");
        assertEq(result.receivingAssetId, MOCK_RECEIVING_ASSET_ID, "Test Case 1 Failed: receivingAssetId mismatch");
        assertEq(
            result.sendingAssetId,
            MOCK_SENDING_ASSET_BRIDGE,
            "Test Case 1 Failed: sendingAssetId should be from bridgeData"
        );
        assertEq(result.receiver, MOCK_RECEIVER, "Test Case 1 Failed: receiver mismatch");
        assertEq(result.destinationChainId, MOCK_DEST_CHAIN_ID, "Test Case 1 Failed: Destination chain ID mismatch");
        assertEq(result.minAmount, MOCK_MIN_AMOUNT_BRIDGE, "Test Case 1 Failed: minAmount mismatch");
    }

    // -------------------------------------------------------------------------
    // Tests for validateRelayInfos
    // -------------------------------------------------------------------------

    address constant TOKEN_A = address(0xAAbbCCDdeEFf00112233445566778899aABBcCDd);
    address constant TOKEN_B = address(0xbbccDDEEaABBCCdDEEfF00112233445566778899);
    uint256 constant OTHER_CHAIN_ID = 42;

    AnypayRelayInfo[] internal _inferredInfos;
    AnypayRelayInfo[] internal _attestedInfos;

    function validateRelayInfosWrapper(
        AnypayRelayInfo[] memory inferredRelayInfos,
        AnypayRelayInfo[] memory attestedRelayInfos
    ) public pure {
        AnypayRelayInterpreter.validateRelayInfos(inferredRelayInfos, attestedRelayInfos);
    }

    function test_ValidateRelayInfos_EmptyArrays() public {
        _inferredInfos = new AnypayRelayInfo[](0);
        _attestedInfos = new AnypayRelayInfo[](0);

        validateRelayInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_MismatchedLengths_Reverts() public {
        _inferredInfos = new AnypayRelayInfo[](1);
        _inferredInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 100, MOCK_TARGET
        );
        _attestedInfos = new AnypayRelayInfo[](0);

        vm.expectRevert(AnypayRelayInterpreter.MismatchedRelayInfoLengths.selector);
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_InferredZeroMinAmount_Reverts() public {
        _inferredInfos = new AnypayRelayInfo[](1);
        _inferredInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 0, MOCK_TARGET
        ); // Zero min amount
        _attestedInfos = new AnypayRelayInfo[](1);
        _attestedInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 100, MOCK_TARGET
        );

        vm.expectRevert(AnypayRelayInterpreter.InvalidInferredMinAmount.selector);
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function test_ValidateRelayInfos_Valid_SingleMatch() public {
        _inferredInfos = new AnypayRelayInfo[](1);
        _inferredInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 100, MOCK_TARGET
        );
        _attestedInfos = new AnypayRelayInfo[](1);
        _attestedInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 100, MOCK_TARGET
        );

        validateRelayInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    function test_ValidateRelayInfos_Valid_SingleMatch_InferredAmountHigher() public {
        _inferredInfos = new AnypayRelayInfo[](1);
        _inferredInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 200, MOCK_TARGET
        ); // Higher inferred
        _attestedInfos = new AnypayRelayInfo[](1);
        _attestedInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 200, MOCK_TARGET
        );

        validateRelayInfosWrapper(_inferredInfos, _attestedInfos); // Should not revert
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_NoMatchingInferred_Reverts() public {
        _inferredInfos = new AnypayRelayInfo[](1);
        _inferredInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 100, MOCK_TARGET
        );
        _attestedInfos = new AnypayRelayInfo[](1);
        _attestedInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_B, address(0), MOCK_DEST_CHAIN_ID, 100, MOCK_TARGET
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                AnypayRelayInterpreter.NoMatchingInferredInfoFound.selector, MOCK_DEST_CHAIN_ID, TOKEN_B
            )
        );
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_InferredAmountTooHigh_Reverts() public {
        _inferredInfos = new AnypayRelayInfo[](1);
        _inferredInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 100, MOCK_TARGET
        );
        _attestedInfos = new AnypayRelayInfo[](1);
        _attestedInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 50, MOCK_TARGET
        );

        vm.expectRevert(abi.encodeWithSelector(AnypayRelayInterpreter.InferredAmountTooHigh.selector, 100, 50));
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    function test_ValidateRelayInfos_MultipleEntries_AllMatch() public {
        _inferredInfos = new AnypayRelayInfo[](2);
        _inferredInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 200, MOCK_TARGET
        );
        _inferredInfos[1] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_B, address(0), OTHER_CHAIN_ID, 100, MOCK_TARGET
        );

        _attestedInfos = new AnypayRelayInfo[](2);
        _attestedInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 200, MOCK_TARGET
        );
        _attestedInfos[1] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_B, address(0), OTHER_CHAIN_ID, 100, MOCK_TARGET
        );

        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_MultipleEntries_NoMatchForOne_Reverts() public {
        _inferredInfos = new AnypayRelayInfo[](2);
        _inferredInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 100, MOCK_TARGET
        );
        _inferredInfos[1] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 100, MOCK_TARGET
        );

        _attestedInfos = new AnypayRelayInfo[](2);
        _attestedInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 100, MOCK_TARGET
        );
        _attestedInfos[1] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_B, address(0), OTHER_CHAIN_ID, 150, MOCK_TARGET
        );

        vm.expectRevert(
            abi.encodeWithSelector(AnypayRelayInterpreter.NoMatchingInferredInfoFound.selector, OTHER_CHAIN_ID, TOKEN_B)
        );
        validateRelayInfosWrapper(_inferredInfos, _attestedInfos);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_ValidateRelayInfos_MultipleEntries_Uniqueness_RevertsIfInferredUsedTwice() public {
        _inferredInfos = new AnypayRelayInfo[](2);
        _inferredInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 300, MOCK_TARGET
        );
        _inferredInfos[1] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_B, address(0), OTHER_CHAIN_ID, 300, MOCK_TARGET
        );

        _attestedInfos = new AnypayRelayInfo[](2);
        _attestedInfos[0] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 300, MOCK_TARGET
        );
        _attestedInfos[1] = AnypayRelayInfo(
            bytes32(0), hex"", bytes32(0), bytes32(0), TOKEN_A, address(0), MOCK_DEST_CHAIN_ID, 300, MOCK_TARGET
        );

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
