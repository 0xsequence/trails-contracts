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
    address payable public recipient;

    // Redeclare event for expectEmit
    event Swept(address indexed token, address indexed recipient, uint256 amount);

    function setUp() public {
        recipient = payable(address(0x1));
        sweeper = new TrailsTokenSweeper();
        erc20 = new ERC20Mock();
    }

    function test_sweep_nativeToken_zeroRecipientEmitsAndSweeps() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);
        vm.deal(address(sweeper), amount);

        vm.expectEmit(true, true, false, true);
        emit Swept(address(0), address(0), amount);
        sweeper.sweep(address(0), address(0));

        assertEq(address(sweeper).balance, 0);
    }

    function test_getBalance_nativeToken() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);
        assertEq(sweeper.getBalance(address(0)), amount);
    }

    function test_getBalance_erc20Token() public {
        uint256 amount = 100 * 1e18;
        erc20.mint(address(this), amount);
        assertEq(sweeper.getBalance(address(erc20)), amount);
    }

    function test_sweep_nativeToken() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);
        vm.deal(address(sweeper), amount);

        uint256 recipientBalanceBefore = recipient.balance;

        vm.expectEmit(true, true, false, true);
        emit Swept(address(0), recipient, amount);
        sweeper.sweep(address(0), recipient);
        uint256 recipientBalanceAfter = recipient.balance;

        assertEq(address(sweeper).balance, 0);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, amount);
    }

    function test_sweep_erc20Token() public {
        uint256 amount = 100 * 1e18;
        erc20.mint(address(this), amount);
        erc20.mint(address(sweeper), amount);

        uint256 recipientBalanceBefore = erc20.balanceOf(recipient);

        vm.expectEmit(true, true, false, true);
        emit Swept(address(erc20), recipient, amount);
        sweeper.sweep(address(erc20), recipient);
        uint256 recipientBalanceAfter = erc20.balanceOf(recipient);

        assertEq(erc20.balanceOf(address(sweeper)), 0);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, amount);
    }

    function test_sweep_noBalance() public {
        uint256 recipientNativeBalanceBefore = recipient.balance;
        vm.deal(address(this), 0);
        vm.expectEmit(true, true, false, true);
        emit Swept(address(0), recipient, 0);
        sweeper.sweep(address(0), recipient);
        uint256 recipientNativeBalanceAfter = recipient.balance;
        assertEq(recipientNativeBalanceAfter, recipientNativeBalanceBefore);

        uint256 recipientErc20BalanceBefore = erc20.balanceOf(recipient);
        vm.expectEmit(true, true, false, true);
        emit Swept(address(erc20), recipient, 0);
        sweeper.sweep(address(erc20), recipient);
        uint256 recipientErc20BalanceAfter = erc20.balanceOf(recipient);
        assertEq(recipientErc20BalanceAfter, recipientErc20BalanceBefore);
    }

    function test_sweep_revertsOnNativeTransferFailure() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);
        vm.deal(address(sweeper), amount);

        RevertingReceiver revertingReceiver = new RevertingReceiver();

        vm.expectRevert(TrailsTokenSweeper.NativeTransferFailed.selector);
        sweeper.sweep(address(0), address(revertingReceiver));

        // Balance remains in sweeper
        assertEq(sweeper.getBalance(address(0)), amount);
    }

    function testFuzz_sweep_nativeToken(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1_000 ether);
        vm.deal(address(this), amount);
        vm.deal(address(sweeper), amount);

        uint256 recipientBalanceBefore = recipient.balance;

        vm.expectEmit(true, true, false, true);
        emit Swept(address(0), recipient, amount);
        sweeper.sweep(address(0), recipient);

        assertEq(address(sweeper).balance, 0);
        assertEq(recipient.balance - recipientBalanceBefore, amount);
    }

    function testFuzz_sweep_erc20Token(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1_000_000_000_000_000_000_000_000);
        erc20.mint(address(this), amount);
        erc20.mint(address(sweeper), amount);

        uint256 recipientBalanceBefore = erc20.balanceOf(recipient);

        vm.expectEmit(true, true, false, true);
        emit Swept(address(erc20), recipient, amount);
        sweeper.sweep(address(erc20), recipient);

        assertEq(erc20.balanceOf(address(sweeper)), 0);
        assertEq(erc20.balanceOf(recipient) - recipientBalanceBefore, amount);
    }
}
