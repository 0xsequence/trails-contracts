// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CallAndOwn, CallAndOwnFactory} from "src/CallAndOwn.sol";

contract MockTarget {
    address public lastCaller;
    uint256 public lastValue;
    uint256 public lastMsgValue;

    function record(uint256 newValue) external payable {
        lastCaller = msg.sender;
        lastValue = newValue;
        lastMsgValue = msg.value;
    }

    function willRevert() external payable {
        revert("MockTarget: revert");
    }
}

contract PayableForwarder {
    function forward(address payable recipient) external payable {
        (bool sent,) = recipient.call{value: msg.value}("");
        require(sent, "forward failed");
    }
}

contract CallAndOwnTest is Test {
    CallAndOwnFactory internal factory;
    MockTarget internal target;
    PayableForwarder internal forwarder;

    address internal owner = makeAddr("owner");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        factory = new CallAndOwnFactory();
        target = new MockTarget();
        forwarder = new PayableForwarder();
    }

    function _creationCodeHash(address _target, uint256 _value, bytes memory _data) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(type(CallAndOwn).creationCode, abi.encode(_target, _value, _data)));
    }

    function _deploy(address _owner, bytes memory initData) internal returns (CallAndOwn deployed, bytes32 creationCodeHash) {
        creationCodeHash = _creationCodeHash(address(target), 0, initData);
        address expected = factory.computeAddress(creationCodeHash, _owner);

        factory.call(_owner, address(target), 0, initData);
        deployed = CallAndOwn(expected);
    }

    function testFactoryDeploysAndPerformsInitialCall() public {
        bytes memory initData = abi.encodeWithSelector(MockTarget.record.selector, 123);
        bytes32 creationCodeHash = _creationCodeHash(address(target), 0, initData);

        address expected = factory.computeAddress(creationCodeHash, owner);
        address manual = vm.computeCreate2Address(bytes32(uint256(uint160(owner))), creationCodeHash, address(factory));
        assertEq(expected, manual);

        factory.call(owner, address(target), 0, initData);

        CallAndOwn deployed = CallAndOwn(expected);
        assertGt(expected.code.length, 0);
        assertEq(deployed.factory(), address(factory));

        assertEq(target.lastCaller(), expected);
        assertEq(target.lastValue(), 123);
        assertEq(target.lastMsgValue(), 0);
    }

    function testOwnerCanCallAsOwnerWithValue() public {
        bytes memory initData = abi.encodeWithSelector(MockTarget.record.selector, 1);
        (CallAndOwn deployed, bytes32 creationCodeHash) = _deploy(owner, initData);

        vm.deal(address(deployed), 1 ether);

        bytes memory callData = abi.encodeWithSelector(MockTarget.record.selector, 999);
        vm.prank(owner);
        deployed.callAsOwner(creationCodeHash, address(target), 0.5 ether, callData);

        assertEq(target.lastCaller(), address(deployed));
        assertEq(target.lastValue(), 999);
        assertEq(target.lastMsgValue(), 0.5 ether);
    }

    function testCallAsOwnerForwardsPayableCallValue() public {
        bytes memory initData = abi.encodeWithSelector(MockTarget.record.selector, 1);
        (CallAndOwn deployed, bytes32 creationCodeHash) = _deploy(owner, initData);

        vm.deal(address(deployed), 1 ether);
        address payable recipient = payable(makeAddr("recipient"));

        bytes memory callData = abi.encodeWithSelector(PayableForwarder.forward.selector, recipient);
        vm.prank(owner);
        deployed.callAsOwner(creationCodeHash, address(forwarder), 0.75 ether, callData);

        assertEq(recipient.balance, 0.75 ether);
        assertEq(address(deployed).balance, 0.25 ether);
    }

    function testCallAsOwnerRevertsForWrongOwner() public {
        bytes memory initData = abi.encodeWithSelector(MockTarget.record.selector, 1);
        (CallAndOwn deployed, bytes32 creationCodeHash) = _deploy(owner, initData);

        vm.expectRevert();
        vm.prank(attacker);
        deployed.callAsOwner(creationCodeHash, address(target), 0, initData);
    }

    function testCallAsOwnerRevertsWithMismatchedCreationCode() public {
        bytes memory initData = abi.encodeWithSelector(MockTarget.record.selector, 1);
        (CallAndOwn deployed,) = _deploy(owner, initData);

        vm.expectRevert();
        vm.prank(owner);
        deployed.callAsOwner(bytes32("wrong"), address(target), 0, initData);
    }

    function testConstructorRevertsWhenInitialCallFails() public {
        bytes memory revertData = abi.encodeWithSelector(MockTarget.willRevert.selector);
        vm.expectRevert();
        factory.call(owner, address(target), 0, revertData);
    }
}
