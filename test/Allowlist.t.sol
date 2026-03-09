// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Allowlist} from "src/autoRecovery/Allowlist.sol";

contract AllowlistTest is Test {
  Allowlist public allowlist;

  address owner = address(0xA);
  address alice = address(0xB);
  address bob = address(0xC);
  address charlie = address(0xD);

  event AddressAdded(address indexed addr);
  event AddressRemoved(address indexed addr);

  function setUp() public {
    address[] memory initial = new address[](0);
    allowlist = new Allowlist(owner, initial);
  }

  // -- Constructor --

  function test_constructor_emptyInitial() external view {
    assertEq(allowlist.owner(), owner);
    assertEq(allowlist.getAllowed().length, 0);
  }

  function test_constructor_withInitial() external {
    address[] memory initial = new address[](2);
    initial[0] = alice;
    initial[1] = bob;
    Allowlist a = new Allowlist(owner, initial);

    assertTrue(a.isAllowed(alice));
    assertTrue(a.isAllowed(bob));
    assertFalse(a.isAllowed(charlie));

    address[] memory all = a.getAllowed();
    assertEq(all.length, 2);
    assertEq(all[0], alice);
    assertEq(all[1], bob);
  }

  function test_constructor_revert_zeroAddress() external {
    address[] memory initial = new address[](1);
    initial[0] = address(0);

    vm.expectRevert(Allowlist.ZeroAddress.selector);
    new Allowlist(owner, initial);
  }

  function test_constructor_revert_duplicateInitial() external {
    address[] memory initial = new address[](2);
    initial[0] = alice;
    initial[1] = alice;

    vm.expectRevert(abi.encodeWithSelector(Allowlist.AlreadyAllowed.selector, alice));
    new Allowlist(owner, initial);
  }

  // -- add --

  function test_add() external {
    vm.prank(owner);
    vm.expectEmit(true, false, false, false);
    emit AddressAdded(alice);
    allowlist.add(alice);

    assertTrue(allowlist.isAllowed(alice));
    assertEq(allowlist.getAllowed().length, 1);
    assertEq(allowlist.getAllowed()[0], alice);
  }

  function test_add_multiple() external {
    vm.startPrank(owner);
    allowlist.add(alice);
    allowlist.add(bob);
    vm.stopPrank();

    assertTrue(allowlist.isAllowed(alice));
    assertTrue(allowlist.isAllowed(bob));
    assertEq(allowlist.getAllowed().length, 2);
  }

  function test_add_revert_alreadyAllowed() external {
    vm.startPrank(owner);
    allowlist.add(alice);

    vm.expectRevert(abi.encodeWithSelector(Allowlist.AlreadyAllowed.selector, alice));
    allowlist.add(alice);
    vm.stopPrank();
  }

  function test_add_revert_zeroAddress() external {
    vm.prank(owner);
    vm.expectRevert(Allowlist.ZeroAddress.selector);
    allowlist.add(address(0));
  }

  function test_add_revert_notOwner() external {
    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    allowlist.add(bob);
  }

  // -- remove with index 0 (search) --

  function test_remove_searchMode_firstElement() external {
    vm.startPrank(owner);
    allowlist.add(alice);
    allowlist.add(bob);

    vm.expectEmit(true, false, false, false);
    emit AddressRemoved(alice);
    allowlist.remove(alice, 0);
    vm.stopPrank();

    assertFalse(allowlist.isAllowed(alice));
    address[] memory all = allowlist.getAllowed();
    assertEq(all.length, 1);
    assertEq(all[0], bob);
  }

  function test_remove_searchMode_lastElement() external {
    vm.startPrank(owner);
    allowlist.add(alice);
    allowlist.add(bob);

    allowlist.remove(bob, 0);
    vm.stopPrank();

    assertFalse(allowlist.isAllowed(bob));
    address[] memory all = allowlist.getAllowed();
    assertEq(all.length, 1);
    assertEq(all[0], alice);
  }

  function test_remove_searchMode_onlyElement() external {
    vm.startPrank(owner);
    allowlist.add(alice);

    allowlist.remove(alice, 0);
    vm.stopPrank();

    assertFalse(allowlist.isAllowed(alice));
    assertEq(allowlist.getAllowed().length, 0);
  }

  // -- remove with index (direct) --

  function test_remove_withIndex() external {
    vm.startPrank(owner);
    allowlist.add(alice);
    allowlist.add(bob);
    allowlist.add(charlie);

    // Remove bob at index 1
    vm.expectEmit(true, false, false, false);
    emit AddressRemoved(bob);
    allowlist.remove(bob, 1);
    vm.stopPrank();

    assertFalse(allowlist.isAllowed(bob));
    address[] memory all = allowlist.getAllowed();
    assertEq(all.length, 2);
    assertEq(all[0], alice);
    assertEq(all[1], charlie);
  }

  function test_remove_withIndex_revert_mismatch() external {
    vm.startPrank(owner);
    allowlist.add(alice);
    allowlist.add(bob);

    // Try to remove alice at index 1 (where bob is)
    vm.expectRevert(abi.encodeWithSelector(Allowlist.IndexMismatch.selector, 1, alice, bob));
    allowlist.remove(alice, 1);
    vm.stopPrank();
  }

  function test_remove_revert_notAllowed() external {
    vm.prank(owner);
    vm.expectRevert(abi.encodeWithSelector(Allowlist.NotAllowed.selector, alice));
    allowlist.remove(alice, 0);
  }

  function test_remove_revert_notOwner() external {
    vm.startPrank(owner);
    allowlist.add(alice);
    vm.stopPrank();

    vm.prank(alice);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
    allowlist.remove(alice, 0);
  }

  // -- isAllowed --

  function test_isAllowed_false() external view {
    assertFalse(allowlist.isAllowed(alice));
  }

  // -- getAllowed --

  function test_getAllowed_empty() external view {
    assertEq(allowlist.getAllowed().length, 0);
  }

  // -- add and remove roundtrip --

  function test_addRemoveAdd() external {
    vm.startPrank(owner);
    allowlist.add(alice);
    allowlist.remove(alice, 0);
    assertFalse(allowlist.isAllowed(alice));

    // Can re-add after removal
    allowlist.add(alice);
    assertTrue(allowlist.isAllowed(alice));
    assertEq(allowlist.getAllowed().length, 1);
    vm.stopPrank();
  }
}
