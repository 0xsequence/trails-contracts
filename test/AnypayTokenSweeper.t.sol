// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AnypayTokenSweeper} from "../../src/AnypayTokenSweeper.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract AnypayTokenSweeperTest is Test {
    AnypayTokenSweeper public sweeper;
    ERC20Mock public erc20;
    address payable public recipient;

    function setUp() public {
        recipient = payable(address(0x1));
        sweeper = new AnypayTokenSweeper(recipient);
        erc20 = new ERC20Mock();
    }

    function test_constructor_revertsIfRecipientIsZeroAddress() public {
        vm.expectRevert("AnypayTokenSweeper: recipient cannot be the zero address");
        new AnypayTokenSweeper(payable(address(0)));
    }

    function test_getBalance_nativeToken() public {
        uint256 amount = 1 ether;
        vm.deal(address(sweeper), amount);
        assertEq(sweeper.getBalance(address(0)), amount);
    }

    function test_getBalance_erc20Token() public {
        uint256 amount = 100 * 1e18;
        erc20.mint(address(sweeper), amount);
        assertEq(sweeper.getBalance(address(erc20)), amount);
    }

    function test_sweep_nativeToken() public {
        uint256 amount = 1 ether;
        vm.deal(address(sweeper), amount);

        uint256 recipientBalanceBefore = recipient.balance;
        sweeper.sweep(address(0));
        uint256 recipientBalanceAfter = recipient.balance;

        assertEq(sweeper.getBalance(address(0)), 0);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, amount);
    }

    function test_sweep_erc20Token() public {
        uint256 amount = 100 * 1e18;
        erc20.mint(address(sweeper), amount);

        uint256 recipientBalanceBefore = erc20.balanceOf(recipient);
        sweeper.sweep(address(erc20));
        uint256 recipientBalanceAfter = erc20.balanceOf(recipient);

        assertEq(sweeper.getBalance(address(erc20)), 0);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, amount);
    }

    function test_sweep_erc20Token_withAmount() public {
        uint256 initialAmount = 100 * 1e18;
        uint256 sweepAmount = 30 * 1e18;
        erc20.mint(address(sweeper), initialAmount);

        uint256 recipientBalanceBefore = erc20.balanceOf(recipient);
        sweeper.sweep(address(erc20), sweepAmount);
        uint256 recipientBalanceAfter = erc20.balanceOf(recipient);

        assertEq(sweeper.getBalance(address(erc20)), initialAmount - sweepAmount);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, sweepAmount);
    }

    function test_sweep_nativeToken_withAmount() public {
        uint256 initialAmount = 2 ether;
        uint256 sweepAmount = 1 ether;
        vm.deal(address(sweeper), initialAmount);

        uint256 recipientBalanceBefore = recipient.balance;
        sweeper.sweep(address(0), sweepAmount);
        uint256 recipientBalanceAfter = recipient.balance;

        assertEq(sweeper.getBalance(address(0)), initialAmount - sweepAmount);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, sweepAmount);
    }

    function test_sweep_revertsIfAmountIsGreaterThanBalance() public {
        uint256 amount = 1 ether;
        vm.deal(address(sweeper), amount);
        vm.expectRevert("AnypayTokenSweeper: insufficient balance");
        sweeper.sweep(address(0), amount + 1);

        uint256 erc20Amount = 100 * 1e18;
        erc20.mint(address(sweeper), erc20Amount);
        vm.expectRevert("AnypayTokenSweeper: insufficient balance");
        sweeper.sweep(address(erc20), erc20Amount + 1);
    }

    function test_sweep_noBalance() public {
        uint256 recipientNativeBalanceBefore = recipient.balance;
        sweeper.sweep(address(0));
        uint256 recipientNativeBalanceAfter = recipient.balance;
        assertEq(recipientNativeBalanceAfter, recipientNativeBalanceBefore);

        uint256 recipientErc20BalanceBefore = erc20.balanceOf(recipient);
        sweeper.sweep(address(erc20));
        uint256 recipientErc20BalanceAfter = erc20.balanceOf(recipient);
        assertEq(recipientErc20BalanceAfter, recipientErc20BalanceBefore);
    }
} 