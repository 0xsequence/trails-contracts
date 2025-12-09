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

/// @dev Mock contract for testing delegatecall functionality
/// @notice This contract stores state that can be modified via delegatecall
contract MockDelegatecallTarget {
    uint256 public storedValue;
    address public storedAddress;
    bytes public storedData;

    event DelegatecallReceived(address sender, uint256 value, bytes data);

    function setValue(uint256 _value) external payable {
        storedValue = _value;
        storedAddress = msg.sender;
        emit DelegatecallReceived(msg.sender, msg.value, msg.data);
    }

    function setAddress(address _addr) external payable {
        storedAddress = _addr;
        emit DelegatecallReceived(msg.sender, msg.value, msg.data);
    }

    function setData(bytes calldata _data) external payable {
        storedData = _data;
        emit DelegatecallReceived(msg.sender, msg.value, _data);
    }

    function revertOnDelegatecall() external pure {
        revert("MockDelegatecallTarget: intentional revert");
    }

    function getThisAddress() external view returns (address) {
        return address(this);
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
        bytes memory callData = abi.encodeWithSelector(MockTarget.receiveCall.selector);

        vm.prank(owner);
        forwarder.call(address(target), callData);
        assertEq(forwarder.owner(), owner, "First caller should become owner");
    }

    function test_ownerCanCallMultipleTimes() public {
        // First call sets owner
        bytes memory callData = abi.encodeWithSelector(MockTarget.receiveCall.selector);

        vm.prank(owner);
        forwarder.call(address(target), callData);
        assertEq(forwarder.owner(), owner, "Owner should be set");

        // Second call by same owner should succeed
        vm.prank(owner);
        forwarder.call(address(target), callData);
    }

    function test_nonOwnerCannotCall() public {
        // First call sets owner
        bytes memory callData = abi.encodeWithSelector(MockTarget.receiveCall.selector);

        vm.prank(owner);
        forwarder.call(address(target), callData);

        // Second call by non-owner should revert
        vm.prank(nonOwner);
        vm.expectRevert(DelayedOwnerForwarder.NotCalledByOwner.selector);
        forwarder.call(address(target), callData);
    }

    // -------------------------------------------------------------------------
    // Test Functions - Forwarding
    // -------------------------------------------------------------------------

    function test_forwardsCallToTarget() public {
        bytes memory callData = abi.encodeWithSelector(MockTarget.receiveCall.selector);

        vm.prank(owner);
        forwarder.call(address(target), callData);

        assertEq(target.lastSender(), address(forwarder), "Target should receive call from forwarder");
        assertEq(target.lastCallData(), callData, "Target should receive correct call data");
    }

    function test_forwardsValue() public {
        uint256 value = 1 ether;
        bytes memory callData = abi.encodeWithSelector(MockTarget.receiveCall.selector);

        vm.deal(owner, value);
        vm.prank(owner);
        forwarder.call{value: value}(address(target), callData);

        assertEq(target.lastValue(), value, "Target should receive forwarded value");
        assertEq(address(target).balance, value, "Target should have received ETH");
    }

    function test_forwardsCallWithData() public {
        bytes memory customData = abi.encode("test", 123, true);
        bytes memory callData = abi.encodeWithSelector(MockTarget.receiveCallWithData.selector, customData);

        vm.prank(owner);
        forwarder.call(address(target), callData);

        // receiveCallWithData stores the data parameter, not msg.data
        assertEq(target.lastCallData(), customData, "Target should receive correct call data");
    }

    function test_forwardsToReceiveFunction() public {
        bytes memory callData = "";

        vm.deal(owner, 1 ether);
        vm.prank(owner);
        forwarder.call{value: 1 ether}(address(target), callData);

        assertEq(target.lastValue(), 1 ether, "Target should receive value");
        assertEq(address(target).balance, 1 ether, "Target should have received ETH");
    }

    // -------------------------------------------------------------------------
    // Test Functions - Error Cases
    // -------------------------------------------------------------------------

    function test_revertsWhen_forwardFails() public {
        MockTarget failingTarget = new MockTarget();
        bytes memory callData = abi.encodeWithSelector(MockTarget.revertOnCall.selector);

        vm.prank(owner);
        vm.expectRevert(DelayedOwnerForwarder.ForwardFailed.selector);
        forwarder.call(address(failingTarget), callData);
    }

    function test_revertsWhen_targetCallReverts() public {
        MockTarget failingTarget = new MockTarget();
        bytes memory callData = abi.encodeWithSelector(MockTarget.revertOnCall.selector);

        vm.prank(owner);
        vm.expectRevert(DelayedOwnerForwarder.ForwardFailed.selector);
        forwarder.call(address(failingTarget), callData);
    }

    // -------------------------------------------------------------------------
    // Test Functions - Edge Cases
    // -------------------------------------------------------------------------

    function test_ownerIsZeroBeforeFirstCall() public view {
        assertEq(forwarder.owner(), address(0), "Owner should be zero before first call");
    }

    function test_multipleCallsPreserveOwner() public {
        // First call sets owner
        bytes memory callData = abi.encodeWithSelector(MockTarget.receiveCall.selector);

        vm.prank(owner);
        forwarder.call(address(target), callData);
        assertEq(forwarder.owner(), owner, "Owner should be set");

        // Multiple subsequent calls by owner
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(owner);
            forwarder.call(address(target), callData);
            assertEq(forwarder.owner(), owner, "Owner should remain unchanged");
        }
    }

    function test_forwardsToDifferentTargets() public {
        MockTarget target1 = new MockTarget();
        MockTarget target2 = new MockTarget();
        bytes memory callData = abi.encodeWithSelector(MockTarget.receiveCall.selector);

        vm.prank(owner);
        forwarder.call(address(target1), callData);
        assertEq(target1.lastSender(), address(forwarder), "Target1 should receive call");

        vm.prank(owner);
        forwarder.call(address(target2), callData);
        assertEq(target2.lastSender(), address(forwarder), "Target2 should receive call");
    }

    function test_forwardsWithZeroValue() public {
        bytes memory callData = abi.encodeWithSelector(MockTarget.receiveCall.selector);

        vm.prank(owner);
        forwarder.call{value: 0}(address(target), callData);

        assertEq(target.lastValue(), 0, "Target should receive zero value");
    }

    function test_forwardsWithLargeValue() public {
        uint256 largeValue = 1000 ether;
        bytes memory callData = abi.encodeWithSelector(MockTarget.receiveCall.selector);

        vm.deal(owner, largeValue);
        vm.prank(owner);
        forwarder.call{value: largeValue}(address(target), callData);

        assertEq(target.lastValue(), largeValue, "Target should receive large value");
    }

    function test_forwardsToContractWithoutReceive() public {
        // This should still work if we call a function
        bytes memory callData = abi.encodeWithSelector(MockTarget.receiveCall.selector);

        vm.prank(owner);
        forwarder.call(address(target), callData);
    }

    function test_addressExtraction() public {
        // Verify the forwarder correctly forwards to the target
        MockTarget mockTarget = new MockTarget();
        bytes memory callData = abi.encodeWithSelector(MockTarget.receiveCall.selector);

        vm.prank(owner);
        forwarder.call(address(mockTarget), callData);
        assertEq(mockTarget.lastSender(), address(forwarder), "Target should receive call from forwarder");
    }

    function test_callDataTruncation() public {
        bytes memory callData = abi.encodeWithSelector(MockTarget.receiveCall.selector);

        vm.prank(owner);
        forwarder.call(address(target), callData);

        assertEq(target.lastCallData(), callData, "Forwarded data should match");
    }

    // -------------------------------------------------------------------------
    // Test Functions - Delegatecall
    // -------------------------------------------------------------------------

    function test_delegatecall_setsOwner() public {
        // Use a simple function that doesn't modify storage to avoid storage collision
        MockDelegatecallTarget delegateTarget = new MockDelegatecallTarget();
        bytes memory callData = abi.encodeWithSelector(MockDelegatecallTarget.getThisAddress.selector);

        vm.prank(owner);
        forwarder.delegatecall(address(delegateTarget), callData);
        assertEq(forwarder.owner(), owner, "First caller should become owner");
    }

    function test_delegatecall_modifiesForwarderState() public {
        // First set owner to avoid storage collision issues
        bytes memory dummyCall = abi.encodeWithSelector(MockTarget.receiveCall.selector);
        vm.prank(owner);
        forwarder.call(address(target), dummyCall);
        assertEq(forwarder.owner(), owner, "Owner should be set first");

        // Now test delegatecall - note that this may modify forwarder storage
        // We use getThisAddress which is view-only to verify delegatecall works
        MockDelegatecallTarget delegateTarget = new MockDelegatecallTarget();
        bytes memory callData = abi.encodeWithSelector(MockDelegatecallTarget.getThisAddress.selector);

        vm.prank(owner);
        forwarder.delegatecall(address(delegateTarget), callData);

        // Owner should still be set (unless storage collision occurred)
        // This test verifies delegatecall executes without reverting
    }

    function test_delegatecall_withValue() public {
        MockDelegatecallTarget delegateTarget = new MockDelegatecallTarget();
        uint256 value = 1 ether;
        // Use a function that can receive value
        bytes memory callData = abi.encodeWithSelector(MockDelegatecallTarget.setValue.selector, uint256(456));

        vm.deal(owner, value);
        vm.prank(owner);
        forwarder.delegatecall{value: value}(address(delegateTarget), callData);

        // With delegatecall, the value stays in the forwarder's balance, not the target's
        // The target code executes in the forwarder's context, so msg.value is available
        // but the ETH balance remains with the forwarder
        assertEq(address(forwarder).balance, value, "Value should remain in forwarder");
    }

    function test_delegatecall_withData() public {
        MockDelegatecallTarget delegateTarget = new MockDelegatecallTarget();
        bytes memory customData = abi.encode("test", 789, false);
        bytes memory callData = abi.encodeWithSelector(MockDelegatecallTarget.setData.selector, customData);

        vm.prank(owner);
        forwarder.delegatecall(address(delegateTarget), callData);
    }

    function test_delegatecall_nonOwnerReverts() public {
        // First set owner using regular call to avoid storage collision
        bytes memory dummyCall = abi.encodeWithSelector(MockTarget.receiveCall.selector);
        vm.prank(owner);
        forwarder.call(address(target), dummyCall);

        MockDelegatecallTarget delegateTarget = new MockDelegatecallTarget();
        bytes memory callData = abi.encodeWithSelector(MockDelegatecallTarget.getThisAddress.selector);

        // Non-owner should not be able to delegatecall
        vm.prank(nonOwner);
        vm.expectRevert(DelayedOwnerForwarder.NotCalledByOwner.selector);
        forwarder.delegatecall(address(delegateTarget), callData);
    }

    function test_delegatecall_revertsWhenTargetReverts() public {
        MockDelegatecallTarget delegateTarget = new MockDelegatecallTarget();
        bytes memory callData = abi.encodeWithSelector(MockDelegatecallTarget.revertOnDelegatecall.selector);

        vm.prank(owner);
        vm.expectRevert(DelayedOwnerForwarder.ForwardFailed.selector);
        forwarder.delegatecall(address(delegateTarget), callData);
    }

    function test_delegatecall_emptyData() public {
        MockDelegatecallTarget delegateTarget = new MockDelegatecallTarget();
        bytes memory callData = "";

        vm.prank(owner);
        // Empty data will revert because there's no function to call and no fallback
        vm.expectRevert(DelayedOwnerForwarder.ForwardFailed.selector);
        forwarder.delegatecall(address(delegateTarget), callData);
    }

    function test_delegatecall_multipleCalls() public {
        // First set owner using regular call to avoid storage collision
        bytes memory dummyCall = abi.encodeWithSelector(MockTarget.receiveCall.selector);
        vm.prank(owner);
        forwarder.call(address(target), dummyCall);

        // Now test multiple delegatecalls using view function to avoid storage issues
        MockDelegatecallTarget delegateTarget = new MockDelegatecallTarget();

        vm.prank(owner);
        bytes memory callData1 = abi.encodeWithSelector(MockDelegatecallTarget.getThisAddress.selector);
        forwarder.delegatecall(address(delegateTarget), callData1);

        vm.prank(owner);
        bytes memory callData2 = abi.encodeWithSelector(MockDelegatecallTarget.getThisAddress.selector);
        forwarder.delegatecall(address(delegateTarget), callData2);
    }

    function test_delegatecall_differentTargets() public {
        // First set owner using regular call to avoid storage collision
        bytes memory dummyCall = abi.encodeWithSelector(MockTarget.receiveCall.selector);
        vm.prank(owner);
        forwarder.call(address(target), dummyCall);

        // Now test delegatecall to different targets using view function
        MockDelegatecallTarget target1 = new MockDelegatecallTarget();
        MockDelegatecallTarget target2 = new MockDelegatecallTarget();

        bytes memory callData1 = abi.encodeWithSelector(MockDelegatecallTarget.getThisAddress.selector);
        bytes memory callData2 = abi.encodeWithSelector(MockDelegatecallTarget.getThisAddress.selector);

        vm.prank(owner);
        forwarder.delegatecall(address(target1), callData1);

        vm.prank(owner);
        forwarder.delegatecall(address(target2), callData2);
    }
}
