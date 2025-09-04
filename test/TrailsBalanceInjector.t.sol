// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/TrailsBalanceInjector.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(allowance[from][msg.sender] >= value, "Insufficient allowance");
        require(balanceOf[from] >= value, "Insufficient balance");

        allowance[from][msg.sender] -= value;
        balanceOf[from] -= value;
        balanceOf[to] += value;
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] = amount;
    }
}

contract MockTarget {
    uint256 public lastAmount;
    bool public shouldRevert;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function deposit(uint256 amount, address receiver) external {
        if (shouldRevert) revert("Target reverted");
        lastAmount = amount;
    }
}

contract TrailsBalanceInjectorTest is Test {
    TrailsBalanceInjector balanceInjector;
    MockERC20 token;
    MockTarget target;

    bytes32 constant PLACEHOLDER = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef;

    function setUp() public {
        balanceInjector = new TrailsBalanceInjector();
        token = new MockERC20();
        target = new MockTarget();
    }

    function testSweepAndCall() public {
        // Mint tokens to the caller (this test contract)
        uint256 tokenBalance = 1000e18;
        token.mint(address(this), tokenBalance);

        // Approve balanceInjector to transfer tokens
        token.approve(address(balanceInjector), tokenBalance);

        // Encode calldata with placeholder
        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));

        // Calculate offset (4 bytes for function selector + 0 bytes for first param)
        uint256 amountOffset = 4;

        // Call sweepAndCall
        balanceInjector.sweepAndCall(address(token), address(target), callData, amountOffset, PLACEHOLDER);

        // Verify target received the correct amount
        assertEq(target.lastAmount(), tokenBalance);

        // Verify token was approved
        assertEq(token.allowance(address(balanceInjector), address(target)), tokenBalance);

        // Verify tokens were transferred from caller to balanceInjector
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(balanceInjector)), tokenBalance);
    }

    function testRevertWhenNoTokens() public {
        // Don't mint any tokens to the caller
        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));

        vm.expectRevert("No tokens to sweep");
        balanceInjector.sweepAndCall(address(token), address(target), callData, 4, PLACEHOLDER);
    }

    function testRevertWhenPlaceholderMismatch() public {
        uint256 tokenBalance = 1000e18;
        token.mint(address(this), tokenBalance);
        token.approve(address(balanceInjector), tokenBalance);

        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));

        bytes32 wrongPlaceholder = 0x1111111111111111111111111111111111111111111111111111111111111111;

        vm.expectRevert("Placeholder mismatch");
        balanceInjector.sweepAndCall(address(token), address(target), callData, 4, wrongPlaceholder);
    }

    function testRevertWhenTargetFails() public {
        uint256 tokenBalance = 1000e18;
        token.mint(address(this), tokenBalance);
        token.approve(address(balanceInjector), tokenBalance);
        target.setShouldRevert(true);

        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));

        vm.expectRevert("Target reverted");
        balanceInjector.sweepAndCall(address(token), address(target), callData, 4, PLACEHOLDER);
    }
}
