// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {PayloadSwitchSapient} from "src/modules/PayloadSwitchSapient.sol";

contract PayloadSwitchSapientTest is Test {
  address internal owner;
  address internal operator;
  address internal secondOperator;
  PayloadSwitchSapient internal sapient;

  event Paused(address indexed account);
  event Unpaused(address indexed account);
  event OperatorSet(address indexed operator, bool allowed);

  function _expectedLeaf(Payload.Decoded memory payload) internal view returns (bytes32) {
    bytes32 anyAddressOpHash = Payload.hashFor(payload, address(0));
    return keccak256(abi.encodePacked("Sequence any address subdigest:\n", anyAddressOpHash));
  }

  function setUp() external {
    owner = makeAddr("owner");
    operator = makeAddr("operator");
    secondOperator = makeAddr("secondOperator");

    address[] memory initialOperators = new address[](1);
    initialOperators[0] = operator;
    sapient = new PayloadSwitchSapient(owner, initialOperators);
  }

  function test_constructor_setsOwner() external {
    assertEq(sapient.owner(), owner);
  }

  function test_constructor_setsOperators() external {
    assertTrue(sapient.isOperator(operator));
    assertFalse(sapient.isOperator(secondOperator));
  }

  function test_paused_defaultsFalse() external {
    assertFalse(sapient.paused());
  }

  function test_recoverSapientSignature_returnsLeafWhenNotPaused() external {
    Payload.Decoded memory payload = Payload.fromDigest(bytes32(uint256(0xdeadbeef)));
    assertFalse(sapient.paused());
    bytes32 h = sapient.recoverSapientSignature(payload, hex"01");
    assertEq(h, _expectedLeaf(payload));
  }

  function test_recoverSapientSignature_revertsWhenPaused() external {
    Payload.Decoded memory payload = Payload.fromDigest(bytes32(uint256(0xabc)));
    vm.prank(owner);
    sapient.pause();
    assertTrue(sapient.paused());
    vm.expectRevert(PayloadSwitchSapient.EnforcedPause.selector);
    sapient.recoverSapientSignature(payload, hex"");
  }

  function test_pause_ownerCanPauseAndUnpause() external {
    Payload.Decoded memory payload = Payload.fromDigest(bytes32(uint256(1)));

    vm.prank(owner);
    vm.expectEmit(true, false, false, false);
    emit Paused(owner);
    sapient.pause();

    vm.expectRevert(PayloadSwitchSapient.EnforcedPause.selector);
    sapient.recoverSapientSignature(payload, "");

    vm.prank(owner);
    vm.expectEmit(true, false, false, false);
    emit Unpaused(owner);
    sapient.unpause();

    assertFalse(sapient.paused());
    bytes32 h = sapient.recoverSapientSignature(payload, hex"");
    assertEq(h, _expectedLeaf(payload));
  }

  function test_pause_operatorCanPauseButCannotUnpause() external {
    vm.prank(operator);
    vm.expectEmit(true, false, false, false);
    emit Paused(operator);
    sapient.pause();

    assertTrue(sapient.paused());

    vm.prank(operator);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, operator));
    sapient.unpause();
  }

  function test_pause_revertsForUnauthorizedCaller() external {
    address outsider = makeAddr("outsider");

    vm.prank(outsider);
    vm.expectRevert(abi.encodeWithSelector(PayloadSwitchSapient.UnauthorizedPauser.selector, outsider));
    sapient.pause();
  }

  function test_pause_revertsWhenAlreadyPaused() external {
    vm.prank(owner);
    sapient.pause();

    vm.prank(owner);
    vm.expectRevert(PayloadSwitchSapient.EnforcedPause.selector);
    sapient.pause();
  }

  function test_unpause_revertsWhenNotPaused() external {
    vm.prank(owner);
    vm.expectRevert(PayloadSwitchSapient.ExpectedPause.selector);
    sapient.unpause();
  }

  function test_setOperator_onlyOwner() external {
    address outsider = makeAddr("outsider");

    vm.prank(outsider);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
    sapient.setOperator(secondOperator, true);
  }

  function test_setOperator_updatesPermission() external {
    vm.prank(owner);
    vm.expectEmit(true, false, false, true);
    emit OperatorSet(secondOperator, true);
    sapient.setOperator(secondOperator, true);

    assertTrue(sapient.isOperator(secondOperator));

    vm.prank(secondOperator);
    sapient.pause();
    assertTrue(sapient.paused());

    vm.prank(owner);
    sapient.unpause();

    vm.prank(owner);
    vm.expectEmit(true, false, false, true);
    emit OperatorSet(secondOperator, false);
    sapient.setOperator(secondOperator, false);

    assertFalse(sapient.isOperator(secondOperator));
  }

  function test_setOperator_revertsOnZeroAddress() external {
    vm.prank(owner);
    vm.expectRevert(PayloadSwitchSapient.ZeroAddress.selector);
    sapient.setOperator(address(0), true);
  }

  function test_constructor_revertsOnZeroOperator() external {
    address[] memory initialOperators = new address[](1);
    initialOperators[0] = address(0);

    vm.expectRevert(PayloadSwitchSapient.ZeroAddress.selector);
    new PayloadSwitchSapient(owner, initialOperators);
  }

  function testFuzz_recoverSapientSignature_whenNotPaused_returnsLeafForPayload(bytes32 digest, bytes memory data)
    external
  {
    Payload.Decoded memory payload = Payload.fromDigest(digest);
    bytes32 h = sapient.recoverSapientSignature(payload, data);
    assertEq(h, _expectedLeaf(payload));
  }

  function testFuzz_recoverSapientSignature_whenPaused_reverts(bytes32 digest, bytes memory data) external {
    Payload.Decoded memory payload = Payload.fromDigest(digest);
    vm.prank(owner);
    sapient.pause();
    vm.expectRevert(PayloadSwitchSapient.EnforcedPause.selector);
    sapient.recoverSapientSignature(payload, data);
  }
}
