// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TrailsTokenSweeper} from "@/TrailsTokenSweeper.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

// Helper receiver that always reverts on receiving native tokens
contract RevertingReceiver {
    receive() external payable {
        revert("RevertingReceiver: revert on receive");
    }
}

contract TrailsTokenSweeperTest is Test {
    TrailsTokenSweeper public sweeper;
    ERC20Mock public erc20;
    address payable public holder; // address that holds balances and hosts the sweeper code
    address payable public recipient; // destination that receives swept funds

    // Redeclare event for expectEmit
    event Sweep(address indexed token, address indexed recipient, uint256 amount);

    function setUp() public {
        holder = payable(address(0xbabe));
        recipient = payable(address(0x1));
        sweeper = new TrailsTokenSweeper();
        erc20 = new ERC20Mock();
    }

    function test_sweep_nativeToken_zeroRecipientEmitsAndSweeps() public {
        uint256 amount = 1 ether;
        vm.deal(holder, amount);
        vm.prank(holder);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), address(0), amount);
        sweeper.sweep{value: amount}(address(0), address(0));

        assertEq(holder.balance, 0);
    }

    function test_getBalance_nativeToken() public {
        uint256 amount = 1 ether;
        vm.deal(holder, amount);
        vm.prank(holder);
        assertEq(sweeper.getBalance(address(0)), amount);
    }

    function test_getBalance_erc20Token() public {
        uint256 amount = 100 * 1e18;
        erc20.mint(holder, amount);
        vm.prank(holder);
        assertEq(sweeper.getBalance(address(erc20)), amount);
    }

    function test_sweep_nativeToken() public {
        uint256 amount = 1 ether;
        vm.deal(holder, amount);

        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(holder);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), recipient, amount);
        sweeper.sweep{value: amount}(address(0), recipient);
        uint256 recipientBalanceAfter = recipient.balance;

        assertEq(holder.balance, 0);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, amount);
    }

    function test_sweep_erc20Token() public {
        uint256 amount = 100 * 1e18;
        erc20.mint(holder, amount);
        vm.prank(holder);
        erc20.approve(address(sweeper), amount);

        uint256 recipientBalanceBefore = erc20.balanceOf(recipient);

        vm.prank(holder);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(erc20), recipient, amount);
        sweeper.sweep(address(erc20), recipient);
        uint256 recipientBalanceAfter = erc20.balanceOf(recipient);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, amount);
    }

    function test_sweep_noBalance() public {
        uint256 recipientNativeBalanceBefore = recipient.balance;
        vm.deal(holder, 0);
        vm.prank(holder);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), recipient, 0);
        sweeper.sweep{value: 0}(address(0), recipient);
        uint256 recipientNativeBalanceAfter = recipient.balance;
        assertEq(recipientNativeBalanceAfter, recipientNativeBalanceBefore);

        uint256 recipientErc20BalanceBefore = erc20.balanceOf(recipient);
        vm.prank(holder);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(erc20), recipient, 0);
        sweeper.sweep(address(erc20), recipient);
        uint256 recipientErc20BalanceAfter = erc20.balanceOf(recipient);
        assertEq(recipientErc20BalanceAfter, recipientErc20BalanceBefore);
    }

    function test_sweep_revertsOnNativeTransferFailure() public {
        uint256 amount = 1 ether;
        vm.deal(holder, amount);

        RevertingReceiver revertingReceiver = new RevertingReceiver();

        vm.prank(holder);
        vm.expectRevert(TrailsTokenSweeper.NativeTransferFailed.selector);
        sweeper.sweep{value: amount}(address(0), address(revertingReceiver));

        // Balance remains in sweeper
        vm.prank(holder);
        assertEq(sweeper.getBalance(address(0)), amount);
    }

    function testFuzz_sweep_nativeToken(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1_000 ether);
        vm.deal(holder, amount);

        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(holder);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), recipient, amount);
        sweeper.sweep{value: amount}(address(0), recipient);

        assertEq(holder.balance, 0);
        assertEq(recipient.balance - recipientBalanceBefore, amount);
    }

    function testFuzz_sweep_erc20Token(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1_000_000_000_000_000_000_000_000);
        erc20.mint(holder, amount);
        vm.prank(holder);
        erc20.approve(address(sweeper), amount);

        uint256 recipientBalanceBefore = erc20.balanceOf(recipient);

        vm.prank(holder);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(erc20), recipient, amount);
        sweeper.sweep(address(erc20), recipient);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(erc20.balanceOf(recipient) - recipientBalanceBefore, amount);
    }
}
