// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {BalanceValidator} from "src/autoRecovery/BalanceValidator.sol";
import {MockERC20} from "test/helpers/Mocks.sol";

contract TimedRefundSapientTest is Test {
  BalanceValidator internal validator;
  MockERC20 internal token;
  address internal wallet;

  function setUp() external {
    wallet = makeAddr("wallet");

    validator = new BalanceValidator();

    token = new MockERC20();
  }

  function test_requireZeroBalance_reverts_whenBalanceIsNotZero(uint256 balance) external {
    vm.assume(balance > 0);
    vm.deal(wallet, balance);

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(BalanceValidator.NonZeroBalance.selector, wallet));
    validator.requireZeroBalance();
  }

  function test_requireZeroERC20Balance_reverts_whenBalanceIsNotZero(uint256 balance) external {
    vm.assume(balance > 0);
    token.mint(wallet, balance);

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(BalanceValidator.NonZeroERC20Balance.selector, address(token), wallet));
    validator.requireZeroERC20Balance(address(token));
  }

  function test_requireZeroBalance_passes_whenBalanceIsZero() external {
    vm.prank(wallet);
    validator.requireZeroBalance();
  }

  function test_requireZeroERC20Balance_passes_whenBalanceIsZero() external {
    vm.prank(wallet);
    validator.requireZeroERC20Balance(address(token));
  }

}
