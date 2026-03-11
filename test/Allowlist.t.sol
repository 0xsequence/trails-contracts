// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {Allowlist} from "src/autoRecovery/Allowlist.sol";

contract AllowlistTest is Test {
  event AddressAdded(address indexed addr);
  event AddressRemoved(address indexed addr);

  function testFuzz_constructor_emptyInitial(address owner_) external {
    vm.assume(owner_ != address(0));

    Allowlist allowlist = _newAllowlist(owner_);

    assertEq(allowlist.owner(), owner_);
    assertEq(allowlist.getAllowed().length, 0);
  }

  function testFuzz_constructor_withInitial(address owner_, address first, address second, address outsider) external {
    vm.assume(owner_ != address(0));
    _assumeDistinctNonZero(first, second, outsider);

    address[] memory initial = new address[](2);
    initial[0] = first;
    initial[1] = second;

    Allowlist allowlist = new Allowlist(owner_, initial);

    assertTrue(allowlist.isAllowed(first));
    assertTrue(allowlist.isAllowed(second));
    assertFalse(allowlist.isAllowed(outsider));

    address[] memory all = allowlist.getAllowed();
    assertEq(all.length, 2);
    assertEq(all[0], first);
    assertEq(all[1], second);
  }

  function testFuzz_constructor_revertsZeroAddress(address owner_, address first) external {
    vm.assume(owner_ != address(0));
    vm.assume(first != address(0));

    address[] memory initial = new address[](2);
    initial[0] = first;
    initial[1] = address(0);

    vm.expectRevert(Allowlist.ZeroAddress.selector);
    new Allowlist(owner_, initial);
  }

  function testFuzz_constructor_revertsDuplicateInitial(address owner_, address addr) external {
    vm.assume(owner_ != address(0));
    vm.assume(addr != address(0));

    address[] memory initial = new address[](2);
    initial[0] = addr;
    initial[1] = addr;

    vm.expectRevert(abi.encodeWithSelector(Allowlist.AlreadyAllowed.selector, addr));
    new Allowlist(owner_, initial);
  }

  function testFuzz_add(address owner_, address addr) external {
    vm.assume(owner_ != address(0));
    vm.assume(addr != address(0));

    Allowlist allowlist = _newAllowlist(owner_);

    vm.prank(owner_);
    vm.expectEmit(true, false, false, false);
    emit AddressAdded(addr);
    allowlist.add(addr);

    assertTrue(allowlist.isAllowed(addr));

    address[] memory all = allowlist.getAllowed();
    assertEq(all.length, 1);
    assertEq(all[0], addr);
  }

  function testFuzz_addBatch_empty(address owner_) external {
    vm.assume(owner_ != address(0));

    Allowlist allowlist = _newAllowlist(owner_);
    address[] memory addrs = new address[](0);

    vm.prank(owner_);
    allowlist.add(addrs);

    assertEq(allowlist.getAllowed().length, 0);
  }

  function testFuzz_addBatch(address owner_, address first, address second) external {
    vm.assume(owner_ != address(0));
    _assumeDistinctNonZero(first, second);

    Allowlist allowlist = _newAllowlist(owner_);
    address[] memory addrs = new address[](2);
    addrs[0] = first;
    addrs[1] = second;

    vm.prank(owner_);
    vm.expectEmit(true, false, false, false);
    emit AddressAdded(first);
    vm.expectEmit(true, false, false, false);
    emit AddressAdded(second);
    allowlist.add(addrs);

    assertTrue(allowlist.isAllowed(first));
    assertTrue(allowlist.isAllowed(second));

    address[] memory all = allowlist.getAllowed();
    assertEq(all.length, 2);
    assertEq(all[0], first);
    assertEq(all[1], second);
  }

  function testFuzz_add_revertsAlreadyAllowed(address owner_, address addr) external {
    vm.assume(owner_ != address(0));
    vm.assume(addr != address(0));

    Allowlist allowlist = _newAllowlist(owner_);

    vm.startPrank(owner_);
    allowlist.add(addr);

    vm.expectRevert(abi.encodeWithSelector(Allowlist.AlreadyAllowed.selector, addr));
    allowlist.add(addr);
    vm.stopPrank();
  }

  function testFuzz_addBatch_revertsDuplicateWithinBatch(address owner_, address addr) external {
    vm.assume(owner_ != address(0));
    vm.assume(addr != address(0));

    Allowlist allowlist = _newAllowlist(owner_);
    address[] memory addrs = new address[](2);
    addrs[0] = addr;
    addrs[1] = addr;

    vm.prank(owner_);
    vm.expectRevert(abi.encodeWithSelector(Allowlist.AlreadyAllowed.selector, addr));
    allowlist.add(addrs);
  }

  function testFuzz_add_revertsZeroAddress(address owner_) external {
    vm.assume(owner_ != address(0));

    Allowlist allowlist = _newAllowlist(owner_);

    vm.prank(owner_);
    vm.expectRevert(Allowlist.ZeroAddress.selector);
    allowlist.add(address(0));
  }

  function testFuzz_addBatch_revertsZeroAddress(address owner_, address addr) external {
    vm.assume(owner_ != address(0));
    vm.assume(addr != address(0));

    Allowlist allowlist = _newAllowlist(owner_);
    address[] memory addrs = new address[](2);
    addrs[0] = addr;
    addrs[1] = address(0);

    vm.prank(owner_);
    vm.expectRevert(Allowlist.ZeroAddress.selector);
    allowlist.add(addrs);
  }

  function testFuzz_add_revertsNotOwner(address owner_, address caller, address addr) external {
    vm.assume(owner_ != address(0));
    vm.assume(caller != owner_);
    vm.assume(addr != address(0));

    Allowlist allowlist = _newAllowlist(owner_);

    vm.prank(caller);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
    allowlist.add(addr);
  }

  function testFuzz_addBatch_revertsNotOwner(address owner_, address caller, address addr) external {
    vm.assume(owner_ != address(0));
    vm.assume(caller != owner_);
    vm.assume(addr != address(0));

    Allowlist allowlist = _newAllowlist(owner_);
    address[] memory addrs = new address[](1);
    addrs[0] = addr;

    vm.prank(caller);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
    allowlist.add(addrs);
  }

  function testFuzz_remove_searchMode(address owner_, address first, address second, bool removeFirst) external {
    vm.assume(owner_ != address(0));
    _assumeDistinctNonZero(first, second);

    Allowlist allowlist = _newAllowlist(owner_);
    address target = removeFirst ? first : second;
    address survivor = removeFirst ? second : first;

    vm.startPrank(owner_);
    allowlist.add(first);
    allowlist.add(second);

    vm.expectEmit(true, false, false, false);
    emit AddressRemoved(target);
    allowlist.remove(target, 0);
    vm.stopPrank();

    assertFalse(allowlist.isAllowed(target));
    assertTrue(allowlist.isAllowed(survivor));

    address[] memory all = allowlist.getAllowed();
    assertEq(all.length, 1);
    assertEq(all[0], survivor);
  }

  function testFuzz_remove_searchMode_onlyElement(address owner_, address addr) external {
    vm.assume(owner_ != address(0));
    vm.assume(addr != address(0));

    Allowlist allowlist = _newAllowlist(owner_);

    vm.startPrank(owner_);
    allowlist.add(addr);
    allowlist.remove(addr, 0);
    vm.stopPrank();

    assertFalse(allowlist.isAllowed(addr));
    assertEq(allowlist.getAllowed().length, 0);
  }

  function testFuzz_removeBatch_empty(address owner_) external {
    vm.assume(owner_ != address(0));

    Allowlist allowlist = _newAllowlist(owner_);
    address[] memory addrs = new address[](0);

    vm.prank(owner_);
    allowlist.remove(addrs);

    assertEq(allowlist.getAllowed().length, 0);
  }

  function testFuzz_removeBatch(
    address owner_,
    address first,
    address second,
    address third,
    bool removeFirstBeforeSecond
  ) external {
    vm.assume(owner_ != address(0));
    _assumeDistinctNonZero(first, second, third);

    Allowlist allowlist = _newAllowlist(owner_);
    address[] memory addrs = new address[](2);
    addrs[0] = removeFirstBeforeSecond ? first : second;
    addrs[1] = removeFirstBeforeSecond ? second : first;

    vm.startPrank(owner_);
    allowlist.add(first);
    allowlist.add(second);
    allowlist.add(third);

    vm.expectEmit(true, false, false, false);
    emit AddressRemoved(addrs[0]);
    vm.expectEmit(true, false, false, false);
    emit AddressRemoved(addrs[1]);
    allowlist.remove(addrs);
    vm.stopPrank();

    assertFalse(allowlist.isAllowed(first));
    assertFalse(allowlist.isAllowed(second));
    assertTrue(allowlist.isAllowed(third));

    address[] memory all = allowlist.getAllowed();
    assertEq(all.length, 1);
    assertEq(all[0], third);
  }

  function testFuzz_remove_withIndex(
    address owner_,
    address first,
    address second,
    address third,
    uint8 removeIndexSeed
  ) external {
    vm.assume(owner_ != address(0));
    _assumeDistinctNonZero(first, second, third);

    Allowlist allowlist = _newAllowlist(owner_);
    uint256 removeIndex = bound(removeIndexSeed, 1, 2);
    address target = removeIndex == 1 ? second : third;

    vm.startPrank(owner_);
    allowlist.add(first);
    allowlist.add(second);
    allowlist.add(third);

    vm.expectEmit(true, false, false, false);
    emit AddressRemoved(target);
    allowlist.remove(target, removeIndex);
    vm.stopPrank();

    assertFalse(allowlist.isAllowed(target));

    address[] memory all = allowlist.getAllowed();
    assertEq(all.length, 2);
    assertEq(all[0], first);
    if (removeIndex == 1) {
      assertEq(all[1], third);
    } else {
      assertEq(all[1], second);
    }
  }

  function testFuzz_remove_withIndex_revertsMismatch(address owner_, address first, address second) external {
    vm.assume(owner_ != address(0));
    _assumeDistinctNonZero(first, second);

    Allowlist allowlist = _newAllowlist(owner_);

    vm.startPrank(owner_);
    allowlist.add(first);
    allowlist.add(second);

    vm.expectRevert(abi.encodeWithSelector(Allowlist.IndexMismatch.selector, 1, first, second));
    allowlist.remove(first, 1);
    vm.stopPrank();
  }

  function testFuzz_remove_revertsNotAllowed(address owner_, address addr, uint256 index) external {
    vm.assume(owner_ != address(0));

    Allowlist allowlist = _newAllowlist(owner_);

    vm.prank(owner_);
    vm.expectRevert(abi.encodeWithSelector(Allowlist.NotAllowed.selector, addr));
    allowlist.remove(addr, index);
  }

  function testFuzz_removeBatch_revertsNotAllowed(address owner_, address addr) external {
    vm.assume(owner_ != address(0));

    Allowlist allowlist = _newAllowlist(owner_);
    address[] memory addrs = new address[](1);
    addrs[0] = addr;

    vm.prank(owner_);
    vm.expectRevert(abi.encodeWithSelector(Allowlist.NotAllowed.selector, addr));
    allowlist.remove(addrs);
  }

  function testFuzz_remove_revertsNotOwner(address owner_, address caller, address addr) external {
    vm.assume(owner_ != address(0));
    vm.assume(caller != owner_);
    vm.assume(addr != address(0));

    Allowlist allowlist = _newAllowlist(owner_);

    vm.prank(owner_);
    allowlist.add(addr);

    vm.prank(caller);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
    allowlist.remove(addr, 0);
  }

  function testFuzz_removeBatch_revertsNotOwner(address owner_, address caller, address addr) external {
    vm.assume(owner_ != address(0));
    vm.assume(caller != owner_);
    vm.assume(addr != address(0));

    Allowlist allowlist = _newAllowlist(owner_);
    address[] memory addrs = new address[](1);
    addrs[0] = addr;

    vm.prank(owner_);
    allowlist.add(addr);

    vm.prank(caller);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, caller));
    allowlist.remove(addrs);
  }

  function testFuzz_isAllowed_false(address owner_, address addr) external {
    vm.assume(owner_ != address(0));

    Allowlist allowlist = _newAllowlist(owner_);

    assertFalse(allowlist.isAllowed(addr));
  }

  function testFuzz_getAllowed_empty(address owner_) external {
    vm.assume(owner_ != address(0));

    Allowlist allowlist = _newAllowlist(owner_);

    assertEq(allowlist.getAllowed().length, 0);
  }

  function testFuzz_addRemoveAdd(address owner_, address addr) external {
    vm.assume(owner_ != address(0));
    vm.assume(addr != address(0));

    Allowlist allowlist = _newAllowlist(owner_);

    vm.startPrank(owner_);
    allowlist.add(addr);
    allowlist.remove(addr, 0);
    assertFalse(allowlist.isAllowed(addr));

    allowlist.add(addr);
    vm.stopPrank();

    assertTrue(allowlist.isAllowed(addr));

    address[] memory all = allowlist.getAllowed();
    assertEq(all.length, 1);
    assertEq(all[0], addr);
  }

  function _newAllowlist(address owner_) private returns (Allowlist) {
    address[] memory initial = new address[](0);
    return new Allowlist(owner_, initial);
  }

  function _assumeDistinctNonZero(address first, address second) private pure {
    vm.assume(first != address(0));
    vm.assume(second != address(0));
    vm.assume(first != second);
  }

  function _assumeDistinctNonZero(address first, address second, address third) private pure {
    vm.assume(first != address(0));
    vm.assume(second != address(0));
    vm.assume(third != address(0));
    vm.assume(first != second);
    vm.assume(first != third);
    vm.assume(second != third);
  }
}
