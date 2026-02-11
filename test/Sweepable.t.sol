// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {Sweepable} from "src/modules/Sweepable.sol";
import {MockERC20} from "test/helpers/Mocks.sol";

contract SweepableTest is Test {
  Sweepable public sweepable;

  function setUp() public {
    sweepable = new Sweepable();
  }

  function testFuzz_sweep(address sweepTarget, uint256[] memory tokenAmounts, uint256 balance, bool sweepNative)
    external
  {
    if (tokenAmounts.length > 2) {
      assembly {
        // Reduce count
        mstore(tokenAmounts, 2)
      }
    }

    address[] memory tokens = new address[](tokenAmounts.length);
    for (uint256 i = 0; i < tokenAmounts.length; i++) {
      MockERC20 token = new MockERC20();
      tokenAmounts[i] = bound(tokenAmounts[i], 1, 10 ether);
      token.mint(address(sweepable), tokenAmounts[i]);
      tokens[i] = address(token);
    }

    assumeUnusedAddress(sweepTarget);
    vm.assume(sweepTarget.balance == 0);

    balance = bound(balance, 1, 10 ether);
    vm.deal(address(sweepable), balance);

    // Expect events
    for (uint256 i = 0; i < tokens.length; i++) {
      vm.expectEmit(true, true, true, true);
      emit Sweepable.Sweep(tokens[i], sweepTarget, tokenAmounts[i]);
    }
    if (sweepNative) {
      vm.expectEmit(true, true, true, true);
      emit Sweepable.Sweep(address(0), sweepTarget, balance);
    }

    sweepable.sweep(sweepTarget, tokens, sweepNative);

    for (uint256 i = 0; i < tokenAmounts.length; i++) {
      assertEq(MockERC20(tokens[i]).balanceOf(sweepTarget), tokenAmounts[i]);
      assertEq(MockERC20(tokens[i]).balanceOf(address(sweepable)), 0);
    }
    if (sweepNative) {
      assertEq(sweepTarget.balance, balance);
      assertEq(address(sweepable).balance, 0);
    } else {
      assertEq(sweepTarget.balance, 0);
      assertEq(address(sweepable).balance, balance);
    }
  }

  function testFuzz_sweepZeroBalances(address sweepTarget, uint256 tokenCount, bool sweepNative) external {
    tokenCount = bound(tokenCount, 0, 2);

    address[] memory tokens = new address[](tokenCount);
    for (uint256 i = 0; i < tokenCount; i++) {
      MockERC20 token = new MockERC20();
      tokens[i] = address(token);
    }

    assumeUnusedAddress(sweepTarget);
    vm.assume(sweepTarget.balance == 0);

    sweepable.sweep(sweepTarget, tokens, sweepNative);

    for (uint256 i = 0; i < tokens.length; i++) {
      assertEq(MockERC20(tokens[i]).balanceOf(sweepTarget), 0);
      assertEq(MockERC20(tokens[i]).balanceOf(address(sweepable)), 0);
    }
    assertEq(sweepTarget.balance, 0);
    assertEq(address(sweepable).balance, 0);
  }
}

