// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {PayloadSwitchSapient} from "src/modules/PayloadSwitchSapient.sol";

contract PayloadSwitchSapientTest is Test {
  address internal owner;
  PayloadSwitchSapient internal sapient;

  function setUp() external {
    owner = makeAddr("owner");
    vm.prank(owner);
    sapient = new PayloadSwitchSapient(owner);
  }

  function test_constructor_setsOwner() external {
    assertEq(sapient.owner(), owner);
  }

  function test_enabled_defaultsFalse() external {
    assertFalse(sapient.enabled());
  }

  function test_recoverSapientSignatureCompact_revertsWhenDisabled() external {
    bytes32 digest = bytes32(uint256(0xabc));
    vm.expectRevert(PayloadSwitchSapient.Disabled.selector);
    sapient.recoverSapientSignatureCompact(digest, hex"");
  }

  function test_setEnabled_owner_allowsRecoverToReturnDigest() external {
    bytes32 digest = bytes32(uint256(0xdeadbeef));
    vm.prank(owner);
    sapient.setEnabled(true);
    assertTrue(sapient.enabled());
    bytes32 h = sapient.recoverSapientSignatureCompact(digest, hex"01");
    assertEq(h, digest);
  }

  function test_setEnabled_owner_canDisableAgain() external {
    bytes32 digest = bytes32(uint256(1));
    vm.startPrank(owner);
    sapient.setEnabled(true);
    sapient.setEnabled(false);
    vm.stopPrank();
    assertFalse(sapient.enabled());
    vm.expectRevert(PayloadSwitchSapient.Disabled.selector);
    sapient.recoverSapientSignatureCompact(digest, "");
  }

  function test_setEnabled_nonOwner_reverts() external {
    vm.prank(makeAddr("notOwner"));
    vm.expectRevert(PayloadSwitchSapient.NotOwner.selector);
    sapient.setEnabled(true);
  }

  function testFuzz_recoverSapientSignatureCompact_whenEnabled_returnsDigest(bytes32 digest, bytes memory data)
    external
  {
    vm.prank(owner);
    sapient.setEnabled(true);
    bytes32 h = sapient.recoverSapientSignatureCompact(digest, data);
    assertEq(h, digest);
  }

  function testFuzz_recoverSapientSignatureCompact_whenDisabled_reverts(bytes32 digest, bytes memory data) external {
    vm.expectRevert(PayloadSwitchSapient.Disabled.selector);
    sapient.recoverSapientSignatureCompact(digest, data);
  }
}
