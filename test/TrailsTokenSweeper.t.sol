// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TrailsTokenSweeper} from "@/TrailsTokenSweeper.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IDelegatedExtension} from "wallet-contracts-v3/modules/interfaces/IDelegatedExtension.sol";

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
    event Refund(address indexed token, address indexed recipient, uint256 amount);

    function setUp() public {
        holder = payable(address(0xbabe));
        recipient = payable(address(0x1));
        sweeper = new TrailsTokenSweeper();
        // Install sweeper runtime code at the holder address to simulate delegatecall context
        vm.etch(holder, address(sweeper).code);
        erc20 = new ERC20Mock();
    }

    function test_sweep_nativeToken_zeroRecipientEmitsAndSweeps() public {
        uint256 amount = 1 ether;
        vm.deal(holder, amount);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), address(0), amount);
        TrailsTokenSweeper(holder).sweep(address(0), address(0));

        assertEq(holder.balance, 0);
    }

    function test_getBalance_nativeToken() public {
        uint256 amount = 1 ether;
        vm.deal(holder, amount);
        vm.prank(holder);
        assertEq(TrailsTokenSweeper(holder).getBalance(address(0)), amount);
    }

    function test_getBalance_erc20Token() public {
        uint256 amount = 100 * 1e18;
        erc20.mint(holder, amount);
        vm.prank(holder);
        assertEq(TrailsTokenSweeper(holder).getBalance(address(erc20)), amount);
    }

    function test_sweep_nativeToken() public {
        uint256 amount = 1 ether;
        vm.deal(holder, amount);

        uint256 recipientBalanceBefore = recipient.balance;

        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), recipient, amount);
        TrailsTokenSweeper(holder).sweep(address(0), recipient);
        uint256 recipientBalanceAfter = recipient.balance;

        assertEq(holder.balance, 0);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, amount);
    }

    function test_sweep_erc20Token() public {
        uint256 amount = 100 * 1e18;
        erc20.mint(holder, amount);
        uint256 recipientBalanceBefore = erc20.balanceOf(recipient);

        vm.expectEmit(true, true, false, true);
        emit Sweep(address(erc20), recipient, amount);
        TrailsTokenSweeper(holder).sweep(address(erc20), recipient);
        uint256 recipientBalanceAfter = erc20.balanceOf(recipient);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, amount);
    }

    function test_sweep_erc20Token_twice_idempotentApproval() public {
        uint256 amount1 = 50 * 1e18;
        uint256 amount2 = 20 * 1e18;

        // First sweep
        erc20.mint(holder, amount1);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(erc20), recipient, amount1);
        TrailsTokenSweeper(holder).sweep(address(erc20), recipient);
        assertEq(erc20.balanceOf(holder), 0);

        // Second sweep after additional mint (should not revert and should transfer)
        erc20.mint(holder, amount2);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(erc20), recipient, amount2);
        TrailsTokenSweeper(holder).sweep(address(erc20), recipient);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(erc20.balanceOf(recipient), amount1 + amount2);
    }

    function test_sweep_noBalance() public {
        uint256 recipientNativeBalanceBefore = recipient.balance;
        vm.deal(holder, 0);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), recipient, 0);
        TrailsTokenSweeper(holder).sweep(address(0), recipient);
        uint256 recipientNativeBalanceAfter = recipient.balance;
        assertEq(recipientNativeBalanceAfter, recipientNativeBalanceBefore);

        uint256 recipientErc20BalanceBefore = erc20.balanceOf(recipient);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(erc20), recipient, 0);
        TrailsTokenSweeper(holder).sweep(address(erc20), recipient);
        uint256 recipientErc20BalanceAfter = erc20.balanceOf(recipient);
        assertEq(recipientErc20BalanceAfter, recipientErc20BalanceBefore);
    }

    function test_sweep_revertsOnNativeTransferFailure() public {
        uint256 amount = 1 ether;
        vm.deal(holder, amount);

        RevertingReceiver revertingReceiver = new RevertingReceiver();

        vm.expectRevert(TrailsTokenSweeper.NativeTransferFailed.selector);
        TrailsTokenSweeper(holder).sweep(address(0), address(revertingReceiver));

        // Balance remains in sweeper
        vm.prank(holder);
        assertEq(TrailsTokenSweeper(holder).getBalance(address(0)), amount);
    }

    function test_refundAndSweep_native_partialRefund() public {
        address refundRecipient = address(0x101);
        address sweepRecipient = address(0x102);

        uint256 amount = 3 ether;
        vm.deal(holder, amount);

        // Expect refund event then sweep event
        vm.expectEmit(true, true, false, true);
        emit Refund(address(0), refundRecipient, 1 ether);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), sweepRecipient, 2 ether);

        TrailsTokenSweeper(holder).refundAndSweep(address(0), refundRecipient, 1 ether, sweepRecipient);

        assertEq(holder.balance, 0);
        assertEq(refundRecipient.balance, 1 ether);
        assertEq(sweepRecipient.balance, 2 ether);
    }

    function test_refundAndSweep_native_refundMoreThanBalance() public {
        address refundRecipient = address(0x201);
        address sweepRecipient = address(0x202);

        uint256 amount = 1 ether;
        vm.deal(holder, amount);

        vm.expectEmit(true, true, false, true);
        emit Refund(address(0), refundRecipient, amount);

        TrailsTokenSweeper(holder).refundAndSweep(address(0), refundRecipient, 5 ether, sweepRecipient);

        assertEq(holder.balance, 0);
        assertEq(refundRecipient.balance, amount);
        assertEq(sweepRecipient.balance, 0);
    }

    function testFuzz_refundAndSweep_native(uint256 total, uint256 refund) public {
        vm.assume(total <= 1_000 ether);
        vm.assume(refund <= 1_000 ether);

        address refundRecipient = address(0xA01);
        address sweepRecipient = address(0xA02);

        vm.deal(holder, total);

        uint256 expectedRefund = refund > total ? total : refund;
        uint256 expectedSweep = total - expectedRefund;

        if (expectedRefund > 0) {
            vm.expectEmit(true, true, false, true);
            emit Refund(address(0), refundRecipient, expectedRefund);
        }
        if (expectedSweep > 0) {
            vm.expectEmit(true, true, false, true);
            emit Sweep(address(0), sweepRecipient, expectedSweep);
        }

        TrailsTokenSweeper(holder).refundAndSweep(address(0), refundRecipient, refund, sweepRecipient);

        assertEq(holder.balance, 0);
        assertEq(refundRecipient.balance, expectedRefund);
        assertEq(sweepRecipient.balance, expectedSweep);
    }

    function testFuzz_refundAndSweep_erc20(uint256 total, uint256 refund) public {
        vm.assume(total > 0 && total <= 1_000_000_000_000_000_000_000_000);
        vm.assume(refund <= 1_000_000_000_000_000_000_000_000);

        address refundRecipient = address(0xB01);
        address sweepRecipient = address(0xB02);

        erc20.mint(holder, total);

        uint256 expectedRefund = refund > total ? total : refund;
        uint256 expectedSweep = total - expectedRefund;

        if (expectedRefund > 0) {
            vm.expectEmit(true, true, false, true);
            emit Refund(address(erc20), refundRecipient, expectedRefund);
        }
        if (expectedSweep > 0) {
            vm.expectEmit(true, true, false, true);
            emit Sweep(address(erc20), sweepRecipient, expectedSweep);
        }

        TrailsTokenSweeper(holder).refundAndSweep(address(erc20), refundRecipient, refund, sweepRecipient);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(erc20.balanceOf(refundRecipient), expectedRefund);
        assertEq(erc20.balanceOf(sweepRecipient), expectedSweep);
    }

    function testFuzz_handleSequenceDelegateCall_refundAndSweep_native(uint256 total, uint256 refund) public {
        vm.assume(total <= 1_000 ether);
        vm.assume(refund <= 1_000 ether);

        address refundRecipient = address(0xC01);
        address sweepRecipient = address(0xC02);

        vm.deal(holder, total);

        uint256 expectedRefund = refund > total ? total : refund;
        uint256 expectedSweep = total - expectedRefund;

        bytes memory data = abi.encodeWithSelector(
            TrailsTokenSweeper.refundAndSweep.selector, address(0), refundRecipient, refund, sweepRecipient
        );

        if (expectedRefund > 0) {
            vm.expectEmit(true, true, false, true);
            emit Refund(address(0), refundRecipient, expectedRefund);
        }
        if (expectedSweep > 0) {
            vm.expectEmit(true, true, false, true);
            emit Sweep(address(0), sweepRecipient, expectedSweep);
        }

        IDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);

        assertEq(holder.balance, 0);
        assertEq(refundRecipient.balance, expectedRefund);
        assertEq(sweepRecipient.balance, expectedSweep);
    }

    function testFuzz_handleSequenceDelegateCall_refundAndSweep_erc20(uint256 total, uint256 refund) public {
        vm.assume(total > 0 && total <= 1_000_000_000_000_000_000_000_000);
        vm.assume(refund <= 1_000_000_000_000_000_000_000_000);

        address refundRecipient = address(0xD01);
        address sweepRecipient = address(0xD02);

        erc20.mint(holder, total);

        uint256 expectedRefund = refund > total ? total : refund;
        uint256 expectedSweep = total - expectedRefund;

        bytes memory data = abi.encodeWithSelector(
            TrailsTokenSweeper.refundAndSweep.selector, address(erc20), refundRecipient, refund, sweepRecipient
        );

        if (expectedRefund > 0) {
            vm.expectEmit(true, true, false, true);
            emit Refund(address(erc20), refundRecipient, expectedRefund);
        }
        if (expectedSweep > 0) {
            vm.expectEmit(true, true, false, true);
            emit Sweep(address(erc20), sweepRecipient, expectedSweep);
        }

        IDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(erc20.balanceOf(refundRecipient), expectedRefund);
        assertEq(erc20.balanceOf(sweepRecipient), expectedSweep);
    }

    function test_refundAndSweep_erc20_partialRefund() public {
        address refundRecipient = address(0x301);
        address sweepRecipient = address(0x302);

        uint256 amount = 300 * 1e18;
        uint256 refund = 120 * 1e18;
        erc20.mint(holder, amount);

        vm.expectEmit(true, true, false, true);
        emit Refund(address(erc20), refundRecipient, refund);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(erc20), sweepRecipient, amount - refund);

        TrailsTokenSweeper(holder).refundAndSweep(address(erc20), refundRecipient, refund, sweepRecipient);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(erc20.balanceOf(refundRecipient), refund);
        assertEq(erc20.balanceOf(sweepRecipient), amount - refund);
    }

    function test_refundAndSweep_erc20_refundMoreThanBalance() public {
        address refundRecipient = address(0x401);
        address sweepRecipient = address(0x402);

        uint256 amount = 100 * 1e18;
        erc20.mint(holder, amount);

        vm.expectEmit(true, true, false, true);
        emit Refund(address(erc20), refundRecipient, amount);

        TrailsTokenSweeper(holder).refundAndSweep(address(erc20), refundRecipient, 500 * 1e18, sweepRecipient);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(erc20.balanceOf(refundRecipient), amount);
        assertEq(erc20.balanceOf(sweepRecipient), 0);
    }

    function test_handleSequenceDelegateCall_dispatches_to_refundAndSweep_native() public {
        address refundRecipient = address(0x501);
        address sweepRecipient = address(0x502);

        uint256 amount = 5 ether;
        vm.deal(holder, amount);

        bytes memory data = abi.encodeWithSelector(
            TrailsTokenSweeper.refundAndSweep.selector, address(0), refundRecipient, 2 ether, sweepRecipient
        );

        vm.expectEmit(true, true, false, true);
        emit Refund(address(0), refundRecipient, 2 ether);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), sweepRecipient, 3 ether);

        IDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);

        assertEq(holder.balance, 0);
        assertEq(refundRecipient.balance, 2 ether);
        assertEq(sweepRecipient.balance, 3 ether);
    }

    function test_handleSequenceDelegateCall_dispatches_to_refundAndSweep_erc20() public {
        address refundRecipient = address(0x601);
        address sweepRecipient = address(0x602);

        uint256 amount = 500 * 1e18;
        uint256 refund = 125 * 1e18;
        erc20.mint(holder, amount);

        bytes memory data = abi.encodeWithSelector(
            TrailsTokenSweeper.refundAndSweep.selector, address(erc20), refundRecipient, refund, sweepRecipient
        );

        vm.expectEmit(true, true, false, true);
        emit Refund(address(erc20), refundRecipient, refund);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(erc20), sweepRecipient, amount - refund);

        IDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(erc20.balanceOf(refundRecipient), refund);
        assertEq(erc20.balanceOf(sweepRecipient), amount - refund);
    }

    function testFuzz_sweep_nativeToken(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1_000 ether);
        vm.deal(holder, amount);

        uint256 recipientBalanceBefore = recipient.balance;

        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), recipient, amount);
        TrailsTokenSweeper(holder).sweep(address(0), recipient);

        assertEq(holder.balance, 0);
        assertEq(recipient.balance - recipientBalanceBefore, amount);
    }

    function testFuzz_sweep_erc20Token(uint256 amount) public {
        vm.assume(amount > 0 && amount <= 1_000_000_000_000_000_000_000_000);
        erc20.mint(holder, amount);
        uint256 recipientBalanceBefore = erc20.balanceOf(recipient);

        vm.expectEmit(true, true, false, true);
        emit Sweep(address(erc20), recipient, amount);
        TrailsTokenSweeper(holder).sweep(address(erc20), recipient);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(erc20.balanceOf(recipient) - recipientBalanceBefore, amount);
    }

    function test_handleSequenceDelegateCall_dispatches_to_sweep_native() public {
        uint256 amount = 1 ether;
        vm.deal(holder, amount);

        // Build delegated call data for sweep(address,address)
        bytes memory data = abi.encodeWithSelector(TrailsTokenSweeper.sweep.selector, address(0), recipient);

        // Expect event from delegated sweep
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), recipient, amount);

        // Call the delegated entrypoint at holder (code installed from sweeper)
        IDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);

        assertEq(holder.balance, 0);
        assertEq(recipient.balance, amount);
    }

    function test_handleSequenceDelegateCall_dispatches_to_sweep_erc20() public {
        uint256 amount = 100 * 1e18;
        erc20.mint(holder, amount);

        bytes memory data = abi.encodeWithSelector(TrailsTokenSweeper.sweep.selector, address(erc20), recipient);

        vm.expectEmit(true, true, false, true);
        emit Sweep(address(erc20), recipient, amount);

        IDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(erc20.balanceOf(recipient), amount);
    }

    function test_handleSequenceDelegateCall_dispatches_to_sweep_erc20_twice() public {
        uint256 amount1 = 40 * 1e18;
        uint256 amount2 = 10 * 1e18;

        bytes memory data = abi.encodeWithSelector(TrailsTokenSweeper.sweep.selector, address(erc20), recipient);

        // First delegated sweep
        erc20.mint(holder, amount1);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(erc20), recipient, amount1);
        IDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);
        assertEq(erc20.balanceOf(holder), 0);

        // Second delegated sweep after additional mint
        erc20.mint(holder, amount2);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(erc20), recipient, amount2);
        IDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(erc20.balanceOf(recipient), amount1 + amount2);
    }

    function test_handleSequenceDelegateCall_invalid_selector_reverts() public {
        // Unknown selector
        bytes memory data = hex"deadbeef";

        vm.expectRevert(
            abi.encodeWithSelector(TrailsTokenSweeper.InvalidDelegatedSelector.selector, bytes4(0xdeadbeef))
        );
        IDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);
    }

    // ---------------------------------------------------------------------
    // validateBalance
    // ---------------------------------------------------------------------

    function test_validateBalance_native_success() public {
        vm.deal(holder, 2 ether);
        uint256 current = TrailsTokenSweeper(holder).validateBalance(address(0), holder, 1 ether);
        assertEq(current, 2 ether);
    }

    function test_validateBalance_native_revert() public {
        vm.deal(holder, 0.5 ether);
        vm.expectRevert(
            abi.encodeWithSelector(TrailsTokenSweeper.InsufficientNativeBalance.selector, holder, 1 ether, 0.5 ether)
        );
        TrailsTokenSweeper(holder).validateBalance(address(0), holder, 1 ether);
    }

    function test_validateBalance_erc20_success() public {
        uint256 amount = 100 * 1e18;
        erc20.mint(holder, amount);
        uint256 current = TrailsTokenSweeper(holder).validateBalance(address(erc20), holder, amount - 1);
        assertEq(current, amount);
    }

    function test_validateBalance_erc20_revert() public {
        vm.expectRevert(
            abi.encodeWithSelector(TrailsTokenSweeper.InsufficientERC20Balance.selector, address(erc20), holder, 1, 0)
        );
        TrailsTokenSweeper(holder).validateBalance(address(erc20), holder, 1);
    }

    // ---------------------------------------------------------------------
    // validateAndSweep
    // ---------------------------------------------------------------------

    function test_validateAndSweep_native_success() public {
        uint256 amount = 3 ether;
        vm.deal(holder, amount);

        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), recipient, amount);

        TrailsTokenSweeper(holder).validateAndSweep(address(0), amount - 1, recipient);

        assertEq(holder.balance, 0);
        assertEq(recipient.balance, amount);
    }

    function test_validateAndSweep_native_revert_when_insufficient() public {
        vm.deal(holder, 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(TrailsTokenSweeper.InsufficientNativeBalance.selector, holder, 2 ether, 1 ether)
        );
        TrailsTokenSweeper(holder).validateAndSweep(address(0), 2 ether, recipient);
        assertEq(holder.balance, 1 ether);
        assertEq(recipient.balance, 0);
    }

    function test_validateAndSweep_erc20_success() public {
        uint256 amount = 250 * 1e18;
        erc20.mint(holder, amount);

        uint256 recipientBefore = erc20.balanceOf(recipient);

        vm.expectEmit(true, true, false, true);
        emit Sweep(address(erc20), recipient, amount);

        TrailsTokenSweeper(holder).validateAndSweep(address(erc20), amount - 1, recipient);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(erc20.balanceOf(recipient) - recipientBefore, amount);
    }

    function test_validateAndSweep_erc20_revert_when_insufficient() public {
        vm.expectRevert(
            abi.encodeWithSelector(TrailsTokenSweeper.InsufficientERC20Balance.selector, address(erc20), holder, 1, 0)
        );
        TrailsTokenSweeper(holder).validateAndSweep(address(erc20), 1, recipient);
        assertEq(erc20.balanceOf(holder), 0);
        assertEq(erc20.balanceOf(recipient), 0);
    }

    function test_handleSequenceDelegateCall_dispatches_to_validateAndSweep_native() public {
        uint256 amount = 7 ether;
        vm.deal(holder, amount);

        bytes memory data =
            abi.encodeWithSelector(TrailsTokenSweeper.validateAndSweep.selector, address(0), amount - 1, recipient);

        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), recipient, amount);

        IDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);
        assertEq(holder.balance, 0);
        assertEq(recipient.balance, amount);
    }

    function test_handleSequenceDelegateCall_dispatches_to_validateAndSweep_erc20() public {
        uint256 amount = 360 * 1e18;
        erc20.mint(holder, amount);

        bytes memory data =
            abi.encodeWithSelector(TrailsTokenSweeper.validateAndSweep.selector, address(erc20), amount - 1, recipient);

        vm.expectEmit(true, true, false, true);
        emit Sweep(address(erc20), recipient, amount);

        IDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);
        assertEq(erc20.balanceOf(holder), 0);
        assertEq(erc20.balanceOf(recipient), amount);
    }
}
