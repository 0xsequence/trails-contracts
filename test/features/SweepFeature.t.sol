// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SweepFeature} from "src/features/SweepFeature.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract SweepFeatureTest is Test {
    SweepFeature public sweepFeature;
    MockERC20 public token;
    address public recipient;
    address public user;

    event Sweep(address indexed token, address indexed recipient, uint256 amount);

    function setUp() public {
        sweepFeature = new SweepFeature();
        token = new MockERC20("Test Token", "TEST", 18);
        recipient = makeAddr("recipient");
        user = makeAddr("user");
    }

    // ============================================================================
    // Test: sweep(address, address) - without maxAmount
    // ============================================================================

    function test_sweep_ERC20_entireBalance() public {
        uint256 amount = 1000e18;
        token.mint(address(sweepFeature), amount);

        uint256 recipientBalanceBefore = token.balanceOf(recipient);

        sweepFeature.sweep(address(token), recipient);

        assertEq(token.balanceOf(recipient), recipientBalanceBefore + amount);
        assertEq(token.balanceOf(address(sweepFeature)), 0);
    }

    function test_sweep_native_entireBalance() public {
        uint256 amount = 10 ether;
        vm.deal(address(sweepFeature), amount);

        uint256 recipientBalanceBefore = recipient.balance;

        sweepFeature.sweep(address(0), recipient);

        assertEq(recipient.balance, recipientBalanceBefore + amount);
        assertEq(address(sweepFeature).balance, 0);
    }

    function test_sweep_ERC20_zeroBalance() public {
        sweepFeature.sweep(address(token), recipient);

        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(address(sweepFeature)), 0);
    }

    function test_sweep_native_zeroBalance() public {
        sweepFeature.sweep(address(0), recipient);

        assertEq(recipient.balance, 0);
        assertEq(address(sweepFeature).balance, 0);
    }

    // ============================================================================
    // Test: sweep(address, address, uint256) - with maxAmount
    // ============================================================================

    function test_sweep_ERC20_withMaxAmount_lessThanBalance() public {
        uint256 balance = 1000e18;
        uint256 maxAmount = 500e18;
        token.mint(address(sweepFeature), balance);

        uint256 recipientBalanceBefore = token.balanceOf(recipient);
        uint256 featureBalanceBefore = token.balanceOf(address(sweepFeature));

        sweepFeature.sweep(address(token), recipient, maxAmount);

        assertEq(token.balanceOf(recipient), recipientBalanceBefore + maxAmount);
        assertEq(token.balanceOf(address(sweepFeature)), featureBalanceBefore - maxAmount);
        assertEq(token.balanceOf(address(sweepFeature)), balance - maxAmount);
    }

    function test_sweep_ERC20_withMaxAmount_greaterThanBalance() public {
        uint256 balance = 500e18;
        uint256 maxAmount = 1000e18;
        token.mint(address(sweepFeature), balance);

        uint256 recipientBalanceBefore = token.balanceOf(recipient);

        sweepFeature.sweep(address(token), recipient, maxAmount);

        assertEq(token.balanceOf(recipient), recipientBalanceBefore + balance);
        assertEq(token.balanceOf(address(sweepFeature)), 0);
    }

    function test_sweep_ERC20_withMaxAmount_equalToBalance() public {
        uint256 amount = 1000e18;
        token.mint(address(sweepFeature), amount);

        uint256 recipientBalanceBefore = token.balanceOf(recipient);

        sweepFeature.sweep(address(token), recipient, amount);

        assertEq(token.balanceOf(recipient), recipientBalanceBefore + amount);
        assertEq(token.balanceOf(address(sweepFeature)), 0);
    }

    function test_sweep_ERC20_withMaxAmount_zero() public {
        uint256 balance = 1000e18;
        token.mint(address(sweepFeature), balance);

        uint256 recipientBalanceBefore = token.balanceOf(recipient);
        uint256 featureBalanceBefore = token.balanceOf(address(sweepFeature));

        sweepFeature.sweep(address(token), recipient, 0);

        assertEq(token.balanceOf(recipient), recipientBalanceBefore);
        assertEq(token.balanceOf(address(sweepFeature)), featureBalanceBefore);
    }

    function test_sweep_native_withMaxAmount_lessThanBalance() public {
        uint256 balance = 10 ether;
        uint256 maxAmount = 5 ether;
        vm.deal(address(sweepFeature), balance);

        uint256 recipientBalanceBefore = recipient.balance;
        uint256 featureBalanceBefore = address(sweepFeature).balance;

        sweepFeature.sweep(address(0), recipient, maxAmount);

        assertEq(recipient.balance, recipientBalanceBefore + maxAmount);
        assertEq(address(sweepFeature).balance, featureBalanceBefore - maxAmount);
        assertEq(address(sweepFeature).balance, balance - maxAmount);
    }

    function test_sweep_native_withMaxAmount_greaterThanBalance() public {
        uint256 balance = 5 ether;
        uint256 maxAmount = 10 ether;
        vm.deal(address(sweepFeature), balance);

        uint256 recipientBalanceBefore = recipient.balance;

        sweepFeature.sweep(address(0), recipient, maxAmount);

        assertEq(recipient.balance, recipientBalanceBefore + balance);
        assertEq(address(sweepFeature).balance, 0);
    }

    function test_sweep_native_withMaxAmount_equalToBalance() public {
        uint256 amount = 10 ether;
        vm.deal(address(sweepFeature), amount);

        uint256 recipientBalanceBefore = recipient.balance;

        sweepFeature.sweep(address(0), recipient, amount);

        assertEq(recipient.balance, recipientBalanceBefore + amount);
        assertEq(address(sweepFeature).balance, 0);
    }

    function test_sweep_native_withMaxAmount_zero() public {
        uint256 balance = 10 ether;
        vm.deal(address(sweepFeature), balance);

        uint256 recipientBalanceBefore = recipient.balance;
        uint256 featureBalanceBefore = address(sweepFeature).balance;

        sweepFeature.sweep(address(0), recipient, 0);

        assertEq(recipient.balance, recipientBalanceBefore);
        assertEq(address(sweepFeature).balance, featureBalanceBefore);
    }

    function test_sweep_native_withMaxAmount_typeMax() public {
        uint256 balance = 10 ether;
        vm.deal(address(sweepFeature), balance);

        uint256 recipientBalanceBefore = recipient.balance;

        sweepFeature.sweep(address(0), recipient, type(uint256).max);

        assertEq(recipient.balance, recipientBalanceBefore + balance);
        assertEq(address(sweepFeature).balance, 0);
    }

    // ============================================================================
    // Test: handleSequenceDelegateCall - with maxAmount
    // ============================================================================

    function test_handleSequenceDelegateCall_ERC20_withMaxAmount() public {
        uint256 balance = 1000e18;
        uint256 maxAmount = 500e18;
        token.mint(address(sweepFeature), balance);

        bytes memory data = abi.encodePacked(address(token), recipient, maxAmount);

        uint256 recipientBalanceBefore = token.balanceOf(recipient);
        uint256 featureBalanceBefore = token.balanceOf(address(sweepFeature));

        sweepFeature.handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);

        assertEq(token.balanceOf(recipient), recipientBalanceBefore + maxAmount);
        assertEq(token.balanceOf(address(sweepFeature)), featureBalanceBefore - maxAmount);
    }

    function test_handleSequenceDelegateCall_ERC20_withoutMaxAmount() public {
        uint256 balance = 1000e18;
        token.mint(address(sweepFeature), balance);

        bytes memory data = abi.encodePacked(address(token), recipient);

        uint256 recipientBalanceBefore = token.balanceOf(recipient);

        sweepFeature.handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);

        assertEq(token.balanceOf(recipient), recipientBalanceBefore + balance);
        assertEq(token.balanceOf(address(sweepFeature)), 0);
    }

    function test_handleSequenceDelegateCall_native_withMaxAmount() public {
        uint256 balance = 10 ether;
        uint256 maxAmount = 5 ether;
        vm.deal(address(sweepFeature), balance);

        bytes memory data = abi.encodePacked(address(0), recipient, maxAmount);

        uint256 recipientBalanceBefore = recipient.balance;
        uint256 featureBalanceBefore = address(sweepFeature).balance;

        sweepFeature.handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);

        assertEq(recipient.balance, recipientBalanceBefore + maxAmount);
        assertEq(address(sweepFeature).balance, featureBalanceBefore - maxAmount);
    }

    function test_handleSequenceDelegateCall_native_withoutMaxAmount() public {
        uint256 balance = 10 ether;
        vm.deal(address(sweepFeature), balance);

        bytes memory data = abi.encodePacked(address(0), recipient);

        uint256 recipientBalanceBefore = recipient.balance;

        sweepFeature.handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);

        assertEq(recipient.balance, recipientBalanceBefore + balance);
        assertEq(address(sweepFeature).balance, 0);
    }

    function test_handleSequenceDelegateCall_ERC20_maxAmount_greaterThanBalance() public {
        uint256 balance = 500e18;
        uint256 maxAmount = 1000e18;
        token.mint(address(sweepFeature), balance);

        bytes memory data = abi.encodePacked(address(token), recipient, maxAmount);

        uint256 recipientBalanceBefore = token.balanceOf(recipient);

        sweepFeature.handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);

        assertEq(token.balanceOf(recipient), recipientBalanceBefore + balance);
        assertEq(token.balanceOf(address(sweepFeature)), 0);
    }

    function test_handleSequenceDelegateCall_native_maxAmount_greaterThanBalance() public {
        uint256 balance = 5 ether;
        uint256 maxAmount = 10 ether;
        vm.deal(address(sweepFeature), balance);

        bytes memory data = abi.encodePacked(address(0), recipient, maxAmount);

        uint256 recipientBalanceBefore = recipient.balance;

        sweepFeature.handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);

        assertEq(recipient.balance, recipientBalanceBefore + balance);
        assertEq(address(sweepFeature).balance, 0);
    }

    // ============================================================================
    // Test: Error cases
    // ============================================================================

    function test_sweep_native_revertingReceiver() public {
        uint256 amount = 10 ether;
        vm.deal(address(sweepFeature), amount);

        RevertingReceiver revertingReceiver = new RevertingReceiver();

        vm.expectRevert(SweepFeature.NativeTransferFailed.selector);
        sweepFeature.sweep(address(0), address(revertingReceiver), amount);
    }

    function test_handleSequenceDelegateCall_native_revertingReceiver() public {
        uint256 amount = 10 ether;
        vm.deal(address(sweepFeature), amount);

        RevertingReceiver revertingReceiver = new RevertingReceiver();

        bytes memory data = abi.encodePacked(address(0), address(revertingReceiver), amount);

        vm.expectRevert(SweepFeature.NativeTransferFailed.selector);
        sweepFeature.handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);
    }

    // ============================================================================
    // Test: Multiple sweeps
    // ============================================================================

    function test_sweep_ERC20_multipleSweeps_partial() public {
        uint256 initialBalance = 1000e18;
        token.mint(address(sweepFeature), initialBalance);

        // First sweep: 300 tokens
        uint256 firstSweep = 300e18;
        sweepFeature.sweep(address(token), recipient, firstSweep);
        assertEq(token.balanceOf(recipient), firstSweep);
        assertEq(token.balanceOf(address(sweepFeature)), initialBalance - firstSweep);

        // Second sweep: 200 tokens
        uint256 secondSweep = 200e18;
        sweepFeature.sweep(address(token), recipient, secondSweep);
        assertEq(token.balanceOf(recipient), firstSweep + secondSweep);
        assertEq(token.balanceOf(address(sweepFeature)), initialBalance - firstSweep - secondSweep);

        // Third sweep: remaining balance (500 tokens)
        sweepFeature.sweep(address(token), recipient);
        assertEq(token.balanceOf(recipient), initialBalance);
        assertEq(token.balanceOf(address(sweepFeature)), 0);
    }

    function test_sweep_native_multipleSweeps_partial() public {
        uint256 initialBalance = 10 ether;
        vm.deal(address(sweepFeature), initialBalance);

        // First sweep: 3 ether
        uint256 firstSweep = 3 ether;
        sweepFeature.sweep(address(0), recipient, firstSweep);
        assertEq(recipient.balance, firstSweep);
        assertEq(address(sweepFeature).balance, initialBalance - firstSweep);

        // Second sweep: 2 ether
        uint256 secondSweep = 2 ether;
        sweepFeature.sweep(address(0), recipient, secondSweep);
        assertEq(recipient.balance, firstSweep + secondSweep);
        assertEq(address(sweepFeature).balance, initialBalance - firstSweep - secondSweep);

        // Third sweep: remaining balance (5 ether)
        sweepFeature.sweep(address(0), recipient);
        assertEq(recipient.balance, initialBalance);
        assertEq(address(sweepFeature).balance, 0);
    }
}

// ============================================================================
// Helper Contracts
// ============================================================================

contract RevertingReceiver {
    receive() external payable {
        revert("RevertingReceiver: revert on receive");
    }
}
