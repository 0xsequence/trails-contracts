// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {TrailsMulticall3Router} from "src/TrailsMulticall3Router.sol";
import {MockSenderGetter} from "test/mocks/MockSenderGetter.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockMulticall3} from "test/mocks/MockMulticall3.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// A malicious token for testing reentrancy vulnerabilities.
contract MaliciousToken is MockERC20 {
    address public reentrantTarget;
    bytes public reentrantCallData;
    bool public reenterOnTransferFrom;
    bool public reenterOnTransfer;

    constructor() MockERC20("Malicious Token", "MAL", 18) {}

    function setReentrantTarget(address _target, bytes calldata _data) external {
        reentrantTarget = _target;
        reentrantCallData = _data;
    }

    function setReenterOnTransfer(bool _reenter) external {
        reenterOnTransfer = _reenter;
    }

    function setReenterOnTransferFrom(bool _reenter) external {
        reenterOnTransferFrom = _reenter;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (reenterOnTransfer && reentrantTarget != address(0)) {
            (bool success,) = reentrantTarget.call(reentrantCallData);
            require(success, "re-entrant call failed");
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (reenterOnTransferFrom && reentrantTarget != address(0)) {
            (bool success,) = reentrantTarget.call(reentrantCallData);
            require(success, "re-entrant call failed");
        }
        return super.transferFrom(from, to, amount);
    }
}

// An attacker contract for orchestrating reentrancy attacks.
contract ReentrancyAttacker {
    enum AttackType {
        None,
        Deposit,
        Withdraw
    }

    TrailsMulticall3Router public router;
    MaliciousToken public token;
    AttackType public attackType;

    constructor(address payable _router, address _token) {
        router = TrailsMulticall3Router(_router);
        token = MaliciousToken(_token);
    }

    function setAttack(AttackType _type) external {
        attackType = _type;
    }

    function attack() external {
        if (attackType == AttackType.Deposit) {
            router.depositToken(address(token), 1 ether);
        } else if (attackType == AttackType.Withdraw) {
            router.withdrawToken(address(token), 1 ether);
        }
    }
}

// An attacker contract specifically for ETH withdrawal reentrancy tests.
contract WithdrawETHReentrancyAttacker {
    TrailsMulticall3Router public router;
    uint256 public constant DEPOSIT_AMOUNT = 1 ether;

    constructor(address payable _router) {
        router = TrailsMulticall3Router(_router);
    }

    function deposit() external payable {
        require(msg.value == DEPOSIT_AMOUNT, "Incorrect deposit amount");
        // Deposit ETH to router by just sending it
        (bool success,) = address(router).call{value: DEPOSIT_AMOUNT}("");
        require(success, "Deposit failed");
    }

    function attack() external {
        router.withdrawETH(DEPOSIT_AMOUNT);
    }

    receive() external payable {
        // Re-enter withdrawETH. This should fail.
        router.withdrawETH(DEPOSIT_AMOUNT);
    }
}

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

    function test_RevertWhen_DepositTokenWithETHAddress() public {
        vm.prank(user);
        vm.expectRevert("Use ETH deposit via execute()");
        multicallWrapper.depositToken(ETH_ADDRESS, 1 ether);
    }

    function test_RevertWhen_DepositTokenWithZeroAmount() public {
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

    function test_RevertWhen_WithdrawETHWithInsufficientBalance() public {
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

    function test_RevertWhen_WithdrawTokenWithETHAddress() public {
        vm.prank(user);
        vm.expectRevert("Use withdrawETH() for ETH");
        multicallWrapper.withdrawToken(ETH_ADDRESS, 1 ether);
    }

    function test_RevertWhen_WithdrawTokenWithInsufficientBalance() public {
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

contract TrailsMulticall3RouterReentrancyTest is Test {
    TrailsMulticall3Router public router;
    MaliciousToken public malToken;
    ReentrancyAttacker public attacker;

    address private constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address internal user = makeAddr("user");

    function setUp() public {
        router = new TrailsMulticall3Router();
        malToken = new MaliciousToken();
        attacker = new ReentrancyAttacker(payable(address(router)), address(malToken));
        vm.deal(user, 1 ether);
    }

    function test_RevertWhen_ReentrancyOnDepositToken() public {
        // Setup attacker and malicious token for reentrancy
        malToken.setReentrantTarget(address(attacker), abi.encodeWithSelector(ReentrancyAttacker.attack.selector));
        attacker.setAttack(ReentrancyAttacker.AttackType.Deposit);
        malToken.setReenterOnTransferFrom(true);

        // Fund attacker with malicious tokens
        vm.startPrank(user);
        malToken.mint(user, 1 ether);
        malToken.approve(address(router), 1 ether);

        // Expect the re-entrant call to fail
        vm.expectRevert("re-entrant call failed");
        router.depositToken(address(malToken), 1 ether);
        vm.stopPrank();
    }

    function test_RevertWhen_ReentrancyOnWithdrawToken() public {
        // Setup attacker and malicious token for reentrancy
        malToken.setReentrantTarget(address(attacker), abi.encodeWithSelector(ReentrancyAttacker.attack.selector));
        attacker.setAttack(ReentrancyAttacker.AttackType.Withdraw);
        malToken.setReenterOnTransfer(true);

        // Deposit malicious tokens to the router
        vm.startPrank(user);
        malToken.mint(user, 1 ether);
        malToken.approve(address(router), 1 ether);
        router.depositToken(address(malToken), 1 ether);
        vm.stopPrank();

        assertEq(router.getDeposit(user, address(malToken)), 1 ether);

        // Expect the re-entrant call to fail
        vm.startPrank(user);
        vm.expectRevert("re-entrant call failed");
        router.withdrawToken(address(malToken), 1 ether);
        vm.stopPrank();
    }

    function test_RevertWhen_ReentrancyOnWithdrawETH() public {
        WithdrawETHReentrancyAttacker ethAttacker = new WithdrawETHReentrancyAttacker(payable(address(router)));

        // Fund the attacker and make it deposit to the router
        vm.deal(address(ethAttacker), 1 ether);
        ethAttacker.deposit{value: 1 ether}();

        assertEq(router.getDeposit(address(ethAttacker), ETH_ADDRESS), 1 ether);
        assertEq(address(router).balance, 1 ether);

        // Expect the re-entrant call to fail
        vm.expectRevert("ETH transfer failed");
        ethAttacker.attack();
    }
}
