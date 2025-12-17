// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {Sweep} from "src/modules/Sweep.sol";
import {MockERC20} from "test/helpers/Mocks.sol";

contract SweepTest is Test {
  Sweep public sweep;

  function setUp() public {
    sweep = new Sweep();
  }

  function testFuzz_sweep(address sweepTarget, uint256[] memory tokenAmounts, uint256 balance) external {
    assumeUnusedAddress(sweepTarget);

    vm.assume(tokenAmounts.length > 0);
    if (tokenAmounts.length > 10) {
      assembly {
        // Reduce count
        mstore(tokenAmounts, 10)
      }
    }

    address[] memory tokens = new address[](tokenAmounts.length);
    for (uint256 i = 0; i < tokenAmounts.length; i++) {
      MockERC20 token = new MockERC20();
      token.mint(address(sweep), tokenAmounts[i]);
      tokens[i] = address(token);
    }

    vm.deal(address(sweep), balance);

    sweep.sweep(sweepTarget, tokens);

    for (uint256 i = 0; i < tokenAmounts.length; i++) {
      assertEq(MockERC20(tokens[i]).balanceOf(sweepTarget), tokenAmounts[i]);
      assertEq(MockERC20(tokens[i]).balanceOf(address(sweep)), 0);
    }
    assertEq(sweepTarget.balance, balance);
    assertEq(address(sweep).balance, 0);
  }
}

