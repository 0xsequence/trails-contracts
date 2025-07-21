// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {TrailsMulticall3Router} from "src/TrailsMulticall3Router.sol";
import {MockSenderGetter} from "test/mocks/MockSenderGetter.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockMulticall3} from "test/mocks/MockMulticall3.sol";

contract TrailsMulticall3RouterTest is Test {
    TrailsMulticall3Router internal multicallWrapper;
    MockSenderGetter internal getter;
    MockERC20 internal mockToken;

    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal user = makeAddr("user");

    function setUp() public {
        // Deploy mock multicall3 at the expected address
        MockMulticall3 mockMulticall3 = new MockMulticall3();
        vm.etch(0xcA11bde05977b3631167028862bE2a173976CA11, address(mockMulticall3).code);

        multicallWrapper = new TrailsMulticall3Router();
        getter = new MockSenderGetter();
        mockToken = new MockERC20("MockToken", "MTK", 18);

        vm.deal(user, 10 ether);
        mockToken.mint(user, 1000e18);
    }

    function test_WhenCalledFromEOA_ShouldPreserveRouterAsSender() public {
        address eoa = makeAddr("eoa");

        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](1);
        calls[0] = IMulticall3.Call3({
            target: address(getter),
            allowFailure: false,
            callData: abi.encodeWithSignature("getSender()")
        });

        vm.prank(eoa, eoa);
        IMulticall3.Result[] memory results = multicallWrapper.aggregate3(calls);

        assertTrue(results[0].success, "call should succeed");
        address returnedSender = abi.decode(results[0].returnData, (address));
        assertEq(returnedSender, address(multicallWrapper), "sender should be the router contract");
    }

    function test_WhenCalledFromContract_ShouldPreserveRouterAsSender() public {
        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](1);
        calls[0] = IMulticall3.Call3({
            target: address(getter),
            allowFailure: false,
            callData: abi.encodeWithSignature("getSender()")
        });

        IMulticall3.Result[] memory results = multicallWrapper.aggregate3(calls);
        assertTrue(results[0].success, "call should succeed");
        address returnedSender = abi.decode(results[0].returnData, (address));
        assertEq(returnedSender, address(multicallWrapper), "sender should be the router contract");
    }

    function test_ExecuteWithETH_ShouldTrackDeposit() public {
        uint256 depositAmount = 1 ether;

        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](1);
        calls[0] = IMulticall3.Call3({
            target: address(getter),
            allowFailure: false,
            callData: abi.encodeWithSignature("getSender()")
        });

        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit TrailsMulticall3Router.Deposit(user, ETH_ADDRESS, depositAmount);

        multicallWrapper.aggregate3{value: depositAmount}(calls);

        assertEq(multicallWrapper.getDeposit(user, ETH_ADDRESS), depositAmount);
    }

    function test_ReceiveETH_ShouldTrackDeposit() public {
        uint256 depositAmount = 0.5 ether;

        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit TrailsMulticall3Router.Deposit(user, ETH_ADDRESS, depositAmount);

        (bool success,) = address(multicallWrapper).call{value: depositAmount}("");
        assertTrue(success);

        assertEq(multicallWrapper.getDeposit(user, ETH_ADDRESS), depositAmount);
    }

    function test_DepositToken_ShouldTrackDeposit() public {
        uint256 depositAmount = 100e18;

        vm.startPrank(user);
        mockToken.approve(address(multicallWrapper), depositAmount);

        vm.expectEmit(true, true, false, true);
        emit TrailsMulticall3Router.Deposit(user, address(mockToken), depositAmount);

        multicallWrapper.depositToken(address(mockToken), depositAmount);
        vm.stopPrank();

        assertEq(multicallWrapper.getDeposit(user, address(mockToken)), depositAmount);
        assertEq(mockToken.balanceOf(address(multicallWrapper)), depositAmount);
    }

    function test_DepositToken_RevertWhenETHAddress() public {
        vm.prank(user);
        vm.expectRevert("Use ETH deposit via execute()");
        multicallWrapper.depositToken(ETH_ADDRESS, 1 ether);
    }

    function test_DepositToken_RevertWhenZeroAmount() public {
        vm.prank(user);
        vm.expectRevert("Amount must be greater than 0");
        multicallWrapper.depositToken(address(mockToken), 0);
    }

    function test_WithdrawETH_ShouldUpdateDeposit() public {
        uint256 depositAmount = 2 ether;
        uint256 withdrawAmount = 1 ether;

        vm.prank(user);
        (bool success,) = address(multicallWrapper).call{value: depositAmount}("");
        assertTrue(success);

        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit TrailsMulticall3Router.Withdraw(user, ETH_ADDRESS, withdrawAmount);

        multicallWrapper.withdrawETH(withdrawAmount);

        assertEq(multicallWrapper.getDeposit(user, ETH_ADDRESS), depositAmount - withdrawAmount);
        assertEq(user.balance, 10 ether - depositAmount + withdrawAmount);
    }

    function test_WithdrawETH_RevertWhenInsufficientBalance() public {
        vm.prank(user);
        vm.expectRevert("Insufficient ETH balance");
        multicallWrapper.withdrawETH(1 ether);
    }

    function test_WithdrawToken_ShouldUpdateDeposit() public {
        uint256 depositAmount = 100e18;
        uint256 withdrawAmount = 50e18;

        vm.startPrank(user);
        mockToken.approve(address(multicallWrapper), depositAmount);
        multicallWrapper.depositToken(address(mockToken), depositAmount);

        vm.expectEmit(true, true, false, true);
        emit TrailsMulticall3Router.Withdraw(user, address(mockToken), withdrawAmount);

        multicallWrapper.withdrawToken(address(mockToken), withdrawAmount);
        vm.stopPrank();

        assertEq(multicallWrapper.getDeposit(user, address(mockToken)), depositAmount - withdrawAmount);
        assertEq(mockToken.balanceOf(user), 1000e18 - depositAmount + withdrawAmount);
    }

    function test_WithdrawToken_RevertWhenETHAddress() public {
        vm.prank(user);
        vm.expectRevert("Use withdrawETH() for ETH");
        multicallWrapper.withdrawToken(ETH_ADDRESS, 1 ether);
    }

    function test_WithdrawToken_RevertWhenInsufficientBalance() public {
        vm.prank(user);
        vm.expectRevert("Insufficient token balance");
        multicallWrapper.withdrawToken(address(mockToken), 1e18);
    }

    function test_MultipleDepositsAndWithdrawals() public {
        uint256 firstDeposit = 1 ether;
        uint256 secondDeposit = 0.5 ether;
        uint256 withdrawAmount = 0.8 ether;

        vm.startPrank(user);

        (bool success,) = address(multicallWrapper).call{value: firstDeposit}("");
        assertTrue(success);
        assertEq(multicallWrapper.getDeposit(user, ETH_ADDRESS), firstDeposit);

        (success,) = address(multicallWrapper).call{value: secondDeposit}("");
        assertTrue(success);
        assertEq(multicallWrapper.getDeposit(user, ETH_ADDRESS), firstDeposit + secondDeposit);

        multicallWrapper.withdrawETH(withdrawAmount);
        assertEq(multicallWrapper.getDeposit(user, ETH_ADDRESS), firstDeposit + secondDeposit - withdrawAmount);

        vm.stopPrank();
    }

    function test_GetDeposit_ReturnsCorrectBalance() public {
        assertEq(multicallWrapper.getDeposit(user, ETH_ADDRESS), 0);
        assertEq(multicallWrapper.getDeposit(user, address(mockToken)), 0);

        vm.prank(user);
        (bool success,) = address(multicallWrapper).call{value: 1 ether}("");
        assertTrue(success);

        assertEq(multicallWrapper.getDeposit(user, ETH_ADDRESS), 1 ether);
    }
}
