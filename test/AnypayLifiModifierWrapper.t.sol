// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Test, console} from "forge-std/Test.sol";
import {AnypayLifiModifierWrapper} from "src/AnypayLifiModifierWrapper.sol";
import {ILiFi} from "lifi-contracts/Interfaces/ILiFi.sol";
import {LibSwap} from "lifi-contracts/Libraries/LibSwap.sol";

contract MockLiFiFacet {
    event BridgeCallReceived(bytes32 indexed transactionId, address actualReceiver, uint256 valueReceived);
    event NonBridgeCallReceived(uint256 data, uint256 valueReceived);
    event RevertingCallReceived(bytes32 indexed transactionId);

    function mockBridgeFunction(ILiFi.BridgeData calldata _bridgeData, uint256 _someOtherData) external payable {
        console.logBytes32(_bridgeData.transactionId);
        if (_bridgeData.transactionId == bytes32(uint256(0xDEADBEEF))) {
            emit RevertingCallReceived(_bridgeData.transactionId);
            revert("MockFacet: Revert triggered");
        }

        emit BridgeCallReceived(_bridgeData.transactionId, _bridgeData.receiver, msg.value);
        uint256 result = 123 + _someOtherData;
        assembly {
            mstore(0x00, result)
            return(0x00, 0x20)
        }
    }

    function nonBridgeFunction(uint256 data, address addr) external payable {
        console.log("nonBridgeFunction received addr:", addr);
        emit NonBridgeCallReceived(data, msg.value);
        uint256 result = 456;
        assembly {
            mstore(0x00, result)
            return(0x00, 0x20)
        }
    }

    receive() external payable {}
}

contract AnypayLifiModifierWrapperTest is Test {
    AnypayLifiModifierWrapper public wrapper;
    MockLiFiFacet public mockFacet;
    address public user = makeAddr("user");
    address public originalReceiver = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);

    function setUp() public {
        mockFacet = new MockLiFiFacet();
        wrapper = new AnypayLifiModifierWrapper(address(mockFacet));
        deal(user, 10 ether);
    }

    function test_ModifyReceiver_CorrectFunction() public {
        ILiFi.BridgeData memory testData = ILiFi.BridgeData({
            transactionId: bytes32(uint256(1)),
            bridge: "mockBridge",
            integrator: "testWrap",
            referrer: address(0),
            sendingAssetId: address(0),
            receiver: originalReceiver,
            minAmount: 100,
            destinationChainId: 10,
            hasSourceSwaps: false,
            hasDestinationCall: false
        });
        uint256 otherData = 789;

        vm.prank(user);
        vm.expectEmit(true, true, true, true, address(mockFacet));
        emit MockLiFiFacet.BridgeCallReceived(testData.transactionId, user, 1 ether);

        bytes memory callData = abi.encodeCall(mockFacet.mockBridgeFunction, (testData, otherData));
        console.logBytes(callData);

        (bool success, bytes memory returnBytes) = address(wrapper).call{value: 1 ether}(callData);

        assertTrue(success, "Call through wrapper failed");
    }

    function test_Forward_NonMatchingFunction() public {
        uint256 inputData = 999;
        address inputAddr = makeAddr("someAddr");

        vm.prank(user);
        vm.expectEmit(true, false, false, true, address(mockFacet));
        emit MockLiFiFacet.NonBridgeCallReceived(inputData, 0.1 ether);

        bytes memory callData = abi.encodeCall(mockFacet.nonBridgeFunction, (inputData, inputAddr));

        (bool success, bytes memory returnBytes) = address(wrapper).call{value: 0.1 ether}(callData);

        // Assert: Call should still succeed and forward, even though the wrapper
        // might have uselessly modified memory at the receiver offset.
        // The critical check is that the 'inputAddr' parameter wasn't overwritten.
        // (Requires checking the console log from the mock facet execution)
        assertTrue(success, "Non-matching call through wrapper failed");
    }

    function test_RevertPropagation() public {
        ILiFi.BridgeData memory testData = ILiFi.BridgeData({
            transactionId: bytes32(uint256(0xDEADBEEF)),
            bridge: "mockBridge",
            integrator: "testWrap",
            referrer: address(0),
            sendingAssetId: address(0),
            receiver: originalReceiver,
            minAmount: 100,
            destinationChainId: 10,
            hasSourceSwaps: false,
            hasDestinationCall: false
        });
        uint256 otherData = 789;

        bytes memory callData = abi.encodeCall(mockFacet.mockBridgeFunction, (testData, otherData));
        console.logBytes(callData);

        vm.prank(user);
        vm.expectRevert(bytes("MockFacet: Revert triggered"));
        (bool success,) = address(wrapper).call(callData);
    }

    function test_ShortCalldata_NoModificationAttempt() public {
        bytes memory shortCallData = hex"aabbccdd";

        vm.prank(user);
        vm.expectEmit(true, true, true, true, address(wrapper));
        emit AnypayLifiModifierWrapper.ForwardAttempt(0, bytes4(shortCallData), user, false);

        // We also expect the final result event for the unmodified attempt
        // Perform the call and check success. It's expected to fail (return success = false)
        // either in the wrapper (if logic prevents forwarding) or in the mockFacet
        // because the calldata is invalid for any function.
        (bool success, bytes memory returnData) = address(wrapper).call{value: 0.01 ether}(shortCallData);

        assertFalse(success, "Short calldata call unexpectedly succeeded");
    }
}
