// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {PausableSapient} from "src/pausable/PausableSapient.sol";

contract PausableSapientTest is Test {
  bytes32 private constant DIGEST = keccak256("digest");

  address private owner_ = makeAddr("owner");
  address private operator = makeAddr("operator");

  PausableSapient internal sapient;

  function setUp() external {
    address[] memory initialOperators = new address[](1);
    initialOperators[0] = operator;

    sapient = new PausableSapient(owner_, initialOperators);
  }

  function test_recoverSapientSignatureCompact_returnsOneWhenUnpaused() external view {
    bytes32 imageHash = sapient.recoverSapientSignatureCompact(DIGEST, hex"deadbeef");

    assertEq(imageHash, bytes32(uint256(1)));
    assertEq(imageHash, sapient.UNPAUSED_IMAGE_HASH());
  }

  function test_recoverSapientSignatureCompact_returnsZeroWhenPausedByOwner() external {
    vm.prank(owner_);
    sapient.pause();

    bytes32 imageHash = sapient.recoverSapientSignatureCompact(DIGEST, "");

    assertEq(imageHash, bytes32(0));
    assertEq(imageHash, sapient.PAUSED_IMAGE_HASH());
  }

  function test_recoverSapientSignatureCompact_returnsZeroWhenPausedByOperator() external {
    vm.prank(operator);
    sapient.pause();

    bytes32 imageHash = sapient.recoverSapientSignatureCompact(DIGEST, "");

    assertEq(imageHash, bytes32(0));
    assertEq(imageHash, sapient.PAUSED_IMAGE_HASH());
  }

  function test_recoverSapientSignatureCompact_returnsOneAfterOwnerUnpause() external {
    vm.prank(operator);
    sapient.pause();

    vm.prank(owner_);
    sapient.unpause();

    bytes32 imageHash = sapient.recoverSapientSignatureCompact(DIGEST, "");

    assertEq(imageHash, bytes32(uint256(1)));
    assertEq(imageHash, sapient.UNPAUSED_IMAGE_HASH());
  }
}
