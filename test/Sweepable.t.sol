// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {Sweepable} from "src/modules/Sweepable.sol";
import {MockERC20} from "test/helpers/Mocks.sol";

contract ReturnBombERC20 {
  mapping(address => uint256) public balanceOf;

  uint256 internal immutable bombSize;

  constructor(uint256 bombSize_) {
    bombSize = bombSize_;
  }

  function mint(address to, uint256 amount) external {
    balanceOf[to] += amount;
  }

  function transfer(address, uint256) external view returns (bool) {
    uint256 size = bombSize;

    assembly ("memory-safe") {
      let ptr := mload(0x40)
      mstore(0x40, add(ptr, size))
      revert(ptr, size)
    }
  }
}

contract SweepableTest is Test {
  uint256 internal constant GOOD_TOKEN_BALANCE = 2 ether;
  uint256 internal constant BAD_TOKEN_BALANCE = 1 ether;
  uint256 internal constant NATIVE_BALANCE = 3 ether;
  uint256 internal constant RETURN_BOMB_SIZE = 1 << 20;
  uint256 internal constant RETURN_BOMB_GAS_LIMIT = 3_500_000;

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

  function test_sweepReturnBombSkipsFailedTokenAndContinues() external {
    MockERC20 goodToken = new MockERC20();
    ReturnBombERC20 badToken = new ReturnBombERC20(RETURN_BOMB_SIZE);
    address recipient = makeAddr("recipient");

    goodToken.mint(address(sweepable), GOOD_TOKEN_BALANCE);
    badToken.mint(address(sweepable), BAD_TOKEN_BALANCE);
    vm.deal(address(sweepable), NATIVE_BALANCE);

    address[] memory tokensToSweep = new address[](2);
    tokensToSweep[0] = address(badToken);
    tokensToSweep[1] = address(goodToken);

    (bool success,) = address(sweepable).call{gas: RETURN_BOMB_GAS_LIMIT}(
      abi.encodeCall(Sweepable.sweep, (recipient, tokensToSweep, true))
    );

    assertTrue(success);
    assertEq(badToken.balanceOf(address(sweepable)), BAD_TOKEN_BALANCE);
    assertEq(badToken.balanceOf(recipient), 0);
    assertEq(goodToken.balanceOf(address(sweepable)), 0);
    assertEq(goodToken.balanceOf(recipient), GOOD_TOKEN_BALANCE);
    assertEq(address(sweepable).balance, 0);
    assertEq(recipient.balance, NATIVE_BALANCE);
  }
}
