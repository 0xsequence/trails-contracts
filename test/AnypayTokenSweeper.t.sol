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