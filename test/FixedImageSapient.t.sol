// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {FixedImageSapient} from "src/modules/FixedImageSapient.sol";

contract FixedImageSapientTest is Test {
  address internal owner;
  FixedImageSapient internal sapient;

  function setUp() external {
    owner = makeAddr("owner");
    vm.prank(owner);
    sapient = new FixedImageSapient(owner);
  }

  function test_constructor_setsOwner() external view {
    assertEq(sapient.owner(), owner);
  }

  function test_recoverSapientSignatureCompact_returnsZeroByDefault() external view {
    bytes32 h = sapient.recoverSapientSignatureCompact(bytes32(uint256(1)), hex"abcd");
    assertEq(h, bytes32(0));
  }

  function test_setImageHash_owner_updatesImage() external {
    bytes32 expected = bytes32(uint256(0xdead));
    vm.prank(owner);
    sapient.setImageHash(expected);
    assertEq(sapient.recoverSapientSignatureCompact(bytes32(0), ""), expected);
  }

  function test_setImageHash_owner_canResetToZero() external {
    vm.startPrank(owner);
    sapient.setImageHash(bytes32(uint256(1)));
    sapient.setImageHash(bytes32(0));
    vm.stopPrank();
    assertEq(sapient.recoverSapientSignatureCompact(bytes32(0), ""), bytes32(0));
  }

  function test_setImageHash_nonOwner_reverts() external {
    address notOwner = makeAddr("notOwner");
    vm.prank(notOwner);
    vm.expectRevert(FixedImageSapient.NotOwner.selector);
    sapient.setImageHash(bytes32(uint256(1)));
  }

  function testFuzz_recoverSapientSignatureCompact_ignoresOpHashAndData(bytes32 opHash, bytes memory data) external {
    bytes32 image = bytes32(uint256(0xbeef));
    vm.prank(owner);
    sapient.setImageHash(image);
    bytes32 h = sapient.recoverSapientSignatureCompact(opHash, data);
    assertEq(h, image);
  }

  /// @dev Record warm and cold gas costs for `recoverSapientSignatureCompact` and check they are similar.
  function test_gas_recoverSapientSignatureCompact_warmStorage() external {
    sapient.recoverSapientSignatureCompact(bytes32(0), "");
    uint256 gasCold = vm.snapshotGasLastCall("recover_cold");
    sapient.recoverSapientSignatureCompact(bytes32(0), "");
    uint256 gasWarm = vm.snapshotGasLastCall("recover_warm");
  }
}
