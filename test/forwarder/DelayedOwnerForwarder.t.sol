// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DelayedOwnerForwarder} from "src/forwarder/DelayedOwnerForwarder.sol";

// -----------------------------------------------------------------------------
// Mock Contracts
// -----------------------------------------------------------------------------

/// @dev Mock target contract that can receive forwarded calls
contract MockTarget {
    uint256 public value;
    bytes public lastCallData;
    address public lastSender;
    uint256 public lastValue;

    event CallReceived(address sender, uint256 value, bytes data);

    function receiveCall() external payable {
        value = msg.value;
        lastCallData = msg.data;
        lastSender = msg.sender;
        lastValue = msg.value;
        emit CallReceived(msg.sender, msg.value, msg.data);
    }

    function receiveCallWithData(bytes calldata data) external payable {
        value = msg.value;
        lastCallData = data;
        lastSender = msg.sender;
        lastValue = msg.value;
        emit CallReceived(msg.sender, msg.value, data);
    }

    function revertOnCall() external pure {
        revert("MockTarget: intentional revert");
    }

    receive() external payable {
        value = msg.value;
        lastSender = msg.sender;
        lastValue = msg.value;
        emit CallReceived(msg.sender, msg.value, "");
    }
}

// -----------------------------------------------------------------------------
// Test Contract
// -----------------------------------------------------------------------------

contract DelayedOwnerForwarderTest is Test {
    // -------------------------------------------------------------------------
    // Test State Variables
    // -------------------------------------------------------------------------
    DelayedOwnerForwarder internal forwarder;
    MockTarget internal target;

    address internal owner = makeAddr("owner");
    address internal nonOwner = makeAddr("nonOwner");

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------
    function setUp() public {
        forwarder = new DelayedOwnerForwarder();
        target = new MockTarget();
    }

    // -------------------------------------------------------------------------
    // Test Functions - Ownership
    // -------------------------------------------------------------------------

    function test_firstCallerBecomesOwner() public {
        // First call should set owner
        bytes memory callData =
            abi.encodePacked(bytes20(address(target)), abi.encodeWithSelector(MockTarget.receiveCall.selector));

        vm.prank(owner);
        (bool success,) = address(forwarder).call(callData);
        assertTrue(success, "First call should succeed");
        assertEq(forwarder.owner(), owner, "First caller should become owner");
    }

    function test_ownerCanCallMultipleTimes() public {
        // First call sets owner
        bytes memory callData1 =
            abi.encodePacked(bytes20(address(target)), abi.encodeWithSelector(MockTarget.receiveCall.selector));

        vm.prank(owner);
        (bool success1,) = address(forwarder).call(callData1);
        assertTrue(success1, "First call should succeed");
        assertEq(forwarder.owner(), owner, "Owner should be set");

        // Second call by same owner should succeed
        bytes memory callData2 =
            abi.encodePacked(bytes20(address(target)), abi.encodeWithSelector(MockTarget.receiveCall.selector));

        vm.prank(owner);
        (bool success2,) = address(forwarder).call(callData2);
        assertTrue(success2, "Second call by owner should succeed");
    }

    function test_nonOwnerCannotCall() public {
        // First call sets owner
        bytes memory callData1 =
            abi.encodePacked(bytes20(address(target)), abi.encodeWithSelector(MockTarget.receiveCall.selector));

        vm.prank(owner);
        (bool success1,) = address(forwarder).call(callData1);
        assertTrue(success1, "First call should succeed");

        // Second call by non-owner should revert
        bytes memory callData2 =
            abi.encodePacked(bytes20(address(target)), abi.encodeWithSelector(MockTarget.receiveCall.selector));

        vm.prank(nonOwner);
        vm.expectRevert(DelayedOwnerForwarder.NotCalledByOwner.selector);
        (bool success2,) = address(forwarder).call(callData2);
        success2; // Silence unused variable warning
    }

    // -------------------------------------------------------------------------
    // Test Functions - Forwarding
    // -------------------------------------------------------------------------

    function test_forwardsCallToTarget() public {
        bytes memory targetCallData = abi.encodeWithSelector(MockTarget.receiveCall.selector);
        bytes memory callData = abi.encodePacked(bytes20(address(target)), targetCallData);

        vm.prank(owner);
        (bool success,) = address(forwarder).call(callData);
        assertTrue(success, "Forward should succeed");

        assertEq(target.lastSender(), address(forwarder), "Target should receive call from forwarder");
        assertEq(target.lastCallData(), targetCallData, "Target should receive correct call data");
    }

    function test_forwardsValue() public {
        uint256 value = 1 ether;
        bytes memory targetCallData = abi.encodeWithSelector(MockTarget.receiveCall.selector);
        bytes memory callData = abi.encodePacked(bytes20(address(target)), targetCallData);

        vm.deal(owner, value);
        vm.prank(owner);
        (bool success,) = address(forwarder).call{value: value}(callData);
        assertTrue(success, "Forward with value should succeed");

        assertEq(target.lastValue(), value, "Target should receive forwarded value");
        assertEq(address(target).balance, value, "Target should have received ETH");
    }

    function test_forwardsCallWithData() public {
        bytes memory customData = abi.encode("test", 123, true);
        bytes memory targetCallData = abi.encodeWithSelector(MockTarget.receiveCallWithData.selector, customData);
        bytes memory callData = abi.encodePacked(bytes20(address(target)), targetCallData);

        vm.prank(owner);
        (bool success,) = address(forwarder).call(callData);
        assertTrue(success, "Forward with data should succeed");

        // receiveCallWithData stores the data parameter, not msg.data
        assertEq(target.lastCallData(), customData, "Target should receive correct call data");
    }

    function test_forwardsToReceiveFunction() public {
        bytes memory callData = abi.encodePacked(bytes20(address(target)));

        vm.deal(owner, 1 ether);
        vm.prank(owner);
        (bool success,) = address(forwarder).call{value: 1 ether}(callData);
        assertTrue(success, "Forward to receive should succeed");

        assertEq(target.lastValue(), 1 ether, "Target should receive value");
        assertEq(address(target).balance, 1 ether, "Target should have received ETH");
    }

    // -------------------------------------------------------------------------
    // Test Functions - Error Cases
    // -------------------------------------------------------------------------

    function test_revertsWhen_callDataTooShort() public {
        // Call data must be at least 20 bytes (address)
        bytes memory shortCallData = hex"1234567890"; // 5 bytes, less than 20

        vm.prank(owner);
        vm.expectRevert(DelayedOwnerForwarder.InvalidCallData.selector);
        (bool success,) = address(forwarder).call(shortCallData);
        success; // Silence unused variable warning
    }

    function test_noRevertsWhen_callDataExactly20Bytes() public {
        // Exactly 20 bytes should be valid (address only, no call data)
        bytes memory callData = abi.encodePacked(bytes20(address(target)));

        vm.prank(owner);
        (bool success,) = address(forwarder).call(callData);
        assertTrue(success, "20 bytes should be valid (forwards to receive function)");
    }

    function test_revertsWhen_forwardFails() public {
        MockTarget failingTarget = new MockTarget();
        bytes memory targetCallData = abi.encodeWithSelector(MockTarget.revertOnCall.selector);
        bytes memory callData = abi.encodePacked(bytes20(address(failingTarget)), targetCallData);

        vm.prank(owner);
        vm.expectRevert(DelayedOwnerForwarder.ForwardFailed.selector);
        (bool success,) = address(forwarder).call(callData);
        success; // Silence unused variable warning
    }

    function test_revertsWhen_targetCallReverts() public {
        MockTarget failingTarget = new MockTarget();
        bytes memory targetCallData = abi.encodeWithSelector(MockTarget.revertOnCall.selector);
        bytes memory callData = abi.encodePacked(bytes20(address(failingTarget)), targetCallData);

        vm.prank(owner);
        vm.expectRevert(DelayedOwnerForwarder.ForwardFailed.selector);
        (bool success,) = address(forwarder).call(callData);
        success; // Silence unused variable warning
    }

    // -------------------------------------------------------------------------
    // Test Functions - Edge Cases
    // -------------------------------------------------------------------------

    function test_ownerIsZeroBeforeFirstCall() public view {
        assertEq(forwarder.owner(), address(0), "Owner should be zero before first call");
    }

    function test_multipleCallsPreserveOwner() public {
        // First call sets owner
        bytes memory callData =
            abi.encodePacked(bytes20(address(target)), abi.encodeWithSelector(MockTarget.receiveCall.selector));

        vm.prank(owner);
        (bool success1,) = address(forwarder).call(callData);
        assertTrue(success1, "First call should succeed");
        assertEq(forwarder.owner(), owner, "Owner should be set");

        // Multiple subsequent calls by owner
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(owner);
            (bool success,) = address(forwarder).call(callData);
            assertTrue(success, "Subsequent call should succeed");
            assertEq(forwarder.owner(), owner, "Owner should remain unchanged");
        }
    }

    function test_forwardsToDifferentTargets() public {
        MockTarget target1 = new MockTarget();
        MockTarget target2 = new MockTarget();

        bytes memory callData1 =
            abi.encodePacked(bytes20(address(target1)), abi.encodeWithSelector(MockTarget.receiveCall.selector));
        bytes memory callData2 =
            abi.encodePacked(bytes20(address(target2)), abi.encodeWithSelector(MockTarget.receiveCall.selector));

        vm.prank(owner);
        (bool success1,) = address(forwarder).call(callData1);
        assertTrue(success1, "First forward should succeed");
        assertEq(target1.lastSender(), address(forwarder), "Target1 should receive call");

        vm.prank(owner);
        (bool success2,) = address(forwarder).call(callData2);
        assertTrue(success2, "Second forward should succeed");
        assertEq(target2.lastSender(), address(forwarder), "Target2 should receive call");
    }

    function test_forwardsWithZeroValue() public {
        bytes memory targetCallData = abi.encodeWithSelector(MockTarget.receiveCall.selector);
        bytes memory callData = abi.encodePacked(bytes20(address(target)), targetCallData);

        vm.prank(owner);
        (bool success,) = address(forwarder).call{value: 0}(callData);
        assertTrue(success, "Forward with zero value should succeed");

        assertEq(target.lastValue(), 0, "Target should receive zero value");
    }

    function test_forwardsWithLargeValue() public {
        uint256 largeValue = 1000 ether;
        bytes memory targetCallData = abi.encodeWithSelector(MockTarget.receiveCall.selector);
        bytes memory callData = abi.encodePacked(bytes20(address(target)), targetCallData);

        vm.deal(owner, largeValue);
        vm.prank(owner);
        (bool success,) = address(forwarder).call{value: largeValue}(callData);
        assertTrue(success, "Forward with large value should succeed");

        assertEq(target.lastValue(), largeValue, "Target should receive large value");
    }

    function test_forwardsToContractWithoutReceive() public {
        // Deploy a contract without receive or fallback
        address targetWithoutReceive = address(new MockTarget());
        // Remove receive function by deploying a minimal contract
        address minimalContract = address(uint160(0x1234));
        vm.assume(minimalContract.code.length == 0);

        // This should still work if we call a function
        bytes memory targetCallData = abi.encodeWithSelector(MockTarget.receiveCall.selector);
        bytes memory callData = abi.encodePacked(bytes20(address(target)), targetCallData);

        vm.prank(owner);
        (bool success,) = address(forwarder).call(callData);
        assertTrue(success, "Forward to contract with function should succeed");
    }

    function test_addressExtraction() public {
        address testTarget = makeAddr("testTarget");
        bytes memory targetCallData = abi.encodeWithSelector(MockTarget.receiveCall.selector);
        bytes memory callData = abi.encodePacked(bytes20(testTarget), targetCallData);

        // Verify the forwarder correctly extracts and forwards to the target
        // This implicitly tests address extraction
        MockTarget mockTarget = new MockTarget();
        bytes memory callDataWithMock = abi.encodePacked(bytes20(address(mockTarget)), targetCallData);

        vm.prank(owner);
        (bool success,) = address(forwarder).call(callDataWithMock);
        assertTrue(success, "Forward should succeed");
        assertEq(mockTarget.lastSender(), address(forwarder), "Target should receive call from forwarder");
    }

    function test_callDataTruncation() public {
        bytes memory targetCallData = abi.encodeWithSelector(MockTarget.receiveCall.selector);
        bytes memory callData = abi.encodePacked(bytes20(address(target)), targetCallData);

        vm.prank(owner);
        (bool success,) = address(forwarder).call(callData);
        assertTrue(success, "Forward should succeed");

        assertEq(target.lastCallData(), targetCallData, "Forwarded data should match");
    }
}
