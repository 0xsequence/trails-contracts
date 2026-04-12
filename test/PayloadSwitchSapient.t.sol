// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {PayloadSwitchSapient} from "src/modules/PayloadSwitchSapient.sol";

contract PayloadSwitchSapientTest is Test {
  address internal owner;
  PayloadSwitchSapient internal sapient;

  function _expectedLeaf(Payload.Decoded memory payload) internal view returns (bytes32) {
    bytes32 anyAddressOpHash = Payload.hashFor(payload, address(0));
    return keccak256(abi.encodePacked("Sequence any address subdigest:\n", anyAddressOpHash));
  }

  function setUp() external {
    owner = makeAddr("owner");
    vm.prank(owner);
    sapient = new PayloadSwitchSapient(owner);
  }

  function test_constructor_setsOwner() external {
    assertEq(sapient.owner(), owner);
  }

  function test_disabled_defaultsFalse() external {
    assertFalse(sapient.disabled());
  }

  function test_recoverSapientSignature_returnsLeafWhenNotDisabled() external {
    Payload.Decoded memory payload = Payload.fromDigest(bytes32(uint256(0xdeadbeef)));
    assertFalse(sapient.disabled());
    bytes32 h = sapient.recoverSapientSignature(payload, hex"01");
    assertEq(h, _expectedLeaf(payload));
  }

  function test_recoverSapientSignature_revertsWhenDisabled() external {
    Payload.Decoded memory payload = Payload.fromDigest(bytes32(uint256(0xabc)));
    vm.prank(owner);
    sapient.setDisabled(true);
    assertTrue(sapient.disabled());
    vm.expectRevert(PayloadSwitchSapient.Disabled.selector);
    sapient.recoverSapientSignature(payload, hex"");
  }

  function test_setDisabled_owner_canClearAndRecoverAgain() external {
    Payload.Decoded memory payload = Payload.fromDigest(bytes32(uint256(1)));
    vm.startPrank(owner);
    sapient.setDisabled(true);
    vm.expectRevert(PayloadSwitchSapient.Disabled.selector);
    sapient.recoverSapientSignature(payload, "");
    sapient.setDisabled(false);
    vm.stopPrank();
    assertFalse(sapient.disabled());
    bytes32 h = sapient.recoverSapientSignature(payload, hex"");
    assertEq(h, _expectedLeaf(payload));
  }

  function test_setDisabled_nonOwner_reverts() external {
    vm.prank(makeAddr("notOwner"));
    vm.expectRevert(PayloadSwitchSapient.NotOwner.selector);
    sapient.setDisabled(true);
  }

  function testFuzz_recoverSapientSignature_whenNotDisabled_returnsLeafForPayload(bytes32 digest, bytes memory data)
    external
  {
    Payload.Decoded memory payload = Payload.fromDigest(digest);
    bytes32 h = sapient.recoverSapientSignature(payload, data);
    assertEq(h, _expectedLeaf(payload));
  }

  function testFuzz_recoverSapientSignature_whenDisabled_reverts(bytes32 digest, bytes memory data) external {
    Payload.Decoded memory payload = Payload.fromDigest(digest);
    vm.prank(owner);
    sapient.setDisabled(true);
    vm.expectRevert(PayloadSwitchSapient.Disabled.selector);
    sapient.recoverSapientSignature(payload, data);
  }
}
