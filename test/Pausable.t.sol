// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Pausable} from "src/pausable/Pausable.sol";

contract PausableHarness is Pausable {
  constructor(address owner_, address[] memory initialOperators) Pausable(owner_, initialOperators) {}

  function guardedWhenNotPaused() external view whenNotPaused returns (bool) {
    return true;
  }

  function guardedWhenPaused() external view whenPaused returns (bool) {
    return true;
  }
}

contract PausableTest is Test {
  address private owner_ = makeAddr("owner");
  address private operator = makeAddr("operator");
  address private secondOperator = makeAddr("secondOperator");
  address private outsider = makeAddr("outsider");

  event Paused(address indexed account);
  event Unpaused(address indexed account);
  event OperatorSet(address indexed operator, bool allowed);

  function test_constructor_setsOwnerAndOperators() external {
    address[] memory initialOperators = new address[](2);
    initialOperators[0] = operator;
    initialOperators[1] = secondOperator;

    PausableHarness pausable = new PausableHarness(owner_, initialOperators);

    assertEq(pausable.owner(), owner_);
    assertFalse(pausable.paused());
    assertTrue(pausable.isOperator(operator));
    assertTrue(pausable.isOperator(secondOperator));
    assertFalse(pausable.isOperator(outsider));
  }

  function test_constructor_revertsOnZeroOwner() external {
    address[] memory initialOperators = new address[](0);

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
    new PausableHarness(address(0), initialOperators);
  }

  function test_constructor_revertsOnZeroOperator() external {
    address[] memory initialOperators = new address[](1);
    initialOperators[0] = address(0);

    vm.expectRevert(Pausable.ZeroAddress.selector);
    new PausableHarness(owner_, initialOperators);
  }

  function test_ownerCanPauseAndUnpause() external {
    PausableHarness pausable = _newPausable();

    vm.prank(owner_);
    vm.expectEmit(true, false, false, false);
    emit Paused(owner_);
    pausable.pause();

    assertTrue(pausable.paused());

    vm.prank(owner_);
    vm.expectEmit(true, false, false, false);
    emit Unpaused(owner_);
    pausable.unpause();

    assertFalse(pausable.paused());
  }

  function test_operatorCanPauseButCannotUnpause() external {
    PausableHarness pausable = _newPausableWithOperator(operator);

    vm.prank(operator);
    vm.expectEmit(true, false, false, false);
    emit Paused(operator);
    pausable.pause();

    assertTrue(pausable.paused());

    vm.prank(operator);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, operator));
    pausable.unpause();
  }

  function test_pause_revertsForUnauthorizedCaller() external {
    PausableHarness pausable = _newPausable();

    vm.prank(outsider);
    vm.expectRevert(abi.encodeWithSelector(Pausable.UnauthorizedPauser.selector, outsider));
    pausable.pause();
  }

  function test_pause_revertsWhenAlreadyPaused() external {
    PausableHarness pausable = _newPausable();

    vm.prank(owner_);
    pausable.pause();

    vm.prank(owner_);
    vm.expectRevert(Pausable.EnforcedPause.selector);
    pausable.pause();
  }

  function test_unpause_revertsWhenNotPaused() external {
    PausableHarness pausable = _newPausable();

    vm.prank(owner_);
    vm.expectRevert(Pausable.ExpectedPause.selector);
    pausable.unpause();
  }

  function test_setOperator_onlyOwner() external {
    PausableHarness pausable = _newPausable();

    vm.prank(outsider);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
    pausable.setOperator(operator, true);
  }

  function test_setOperator_updatesPermission() external {
    PausableHarness pausable = _newPausable();

    vm.prank(owner_);
    vm.expectEmit(true, false, false, true);
    emit OperatorSet(operator, true);
    pausable.setOperator(operator, true);

    assertTrue(pausable.isOperator(operator));

    vm.prank(operator);
    pausable.pause();
    assertTrue(pausable.paused());

    vm.prank(owner_);
    pausable.unpause();

    vm.prank(owner_);
    vm.expectEmit(true, false, false, true);
    emit OperatorSet(operator, false);
    pausable.setOperator(operator, false);

    assertFalse(pausable.isOperator(operator));

    vm.prank(operator);
    vm.expectRevert(abi.encodeWithSelector(Pausable.UnauthorizedPauser.selector, operator));
    pausable.pause();
  }

  function test_setOperator_revertsOnZeroAddress() external {
    PausableHarness pausable = _newPausable();

    vm.prank(owner_);
    vm.expectRevert(Pausable.ZeroAddress.selector);
    pausable.setOperator(address(0), true);
  }

  function test_whenNotPausedModifier() external {
    PausableHarness pausable = _newPausable();

    assertTrue(pausable.guardedWhenNotPaused());

    vm.prank(owner_);
    pausable.pause();

    vm.expectRevert(Pausable.EnforcedPause.selector);
    pausable.guardedWhenNotPaused();
  }

  function test_whenPausedModifier() external {
    PausableHarness pausable = _newPausable();

    vm.expectRevert(Pausable.ExpectedPause.selector);
    pausable.guardedWhenPaused();

    vm.prank(owner_);
    pausable.pause();

    assertTrue(pausable.guardedWhenPaused());
  }

  function _newPausable() private returns (PausableHarness) {
    address[] memory initialOperators = new address[](0);
    return new PausableHarness(owner_, initialOperators);
  }

  function _newPausableWithOperator(address initialOperator) private returns (PausableHarness) {
    address[] memory initialOperators = new address[](1);
    initialOperators[0] = initialOperator;
    return new PausableHarness(owner_, initialOperators);
  }
}
