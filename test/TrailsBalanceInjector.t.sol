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

contract MockTargetETH {
    uint256 public lastAmount;
    uint256 public receivedETH;
    bool public shouldRevert;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function depositETH(uint256 amount, address receiver) external payable {
        if (shouldRevert) revert("Target reverted");
        lastAmount = amount;
        receivedETH = msg.value;
    }

    // Allow contract to receive ETH
    receive() external payable {}
}

contract TrailsBalanceInjectorTest is Test {
    TrailsBalanceInjector balanceInjector;
    MockERC20 token;
    MockTarget target;
    MockTargetETH targetETH;

    bytes32 constant PLACEHOLDER = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef;

    function setUp() public {
        balanceInjector = new TrailsBalanceInjector();
        token = new MockERC20();
        target = new MockTarget();
        targetETH = new MockTargetETH();
    }

    // ============ ERC20 Tests ============

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

    // ============ ETH Tests ============

    function testSweepAndCallETH() public {
        uint256 ethAmount = 1 ether;

        // Encode calldata with placeholder for ETH
        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));

        // Calculate offset (4 bytes for function selector + 0 bytes for first param)
        uint256 amountOffset = 4;

        // Call sweepAndCall with ETH (token = address(0))
        balanceInjector.sweepAndCall{value: ethAmount}(address(0), address(targetETH), callData, amountOffset, PLACEHOLDER);

        // Verify target received the correct amount in the function parameter
        assertEq(targetETH.lastAmount(), ethAmount);

        // Verify target received the ETH
        assertEq(targetETH.receivedETH(), ethAmount);

        // Verify ETH was transferred to target
        assertEq(address(targetETH).balance, ethAmount);
    }

    function testRevertWhenNoETHSent() public {
        // Encode calldata with placeholder for ETH
        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));

        vm.expectRevert("No ETH sent");
        balanceInjector.sweepAndCall(address(0), address(targetETH), callData, 4, PLACEHOLDER);
    }

    function testRevertWhenETHPlaceholderMismatch() public {
        uint256 ethAmount = 1 ether;
        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));

        bytes32 wrongPlaceholder = 0x1111111111111111111111111111111111111111111111111111111111111111;

        vm.expectRevert("Placeholder mismatch");
        balanceInjector.sweepAndCall{value: ethAmount}(address(0), address(targetETH), callData, 4, wrongPlaceholder);
    }

    function testRevertWhenETHTargetFails() public {
        uint256 ethAmount = 1 ether;
        targetETH.setShouldRevert(true);

        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));

        vm.expectRevert("Target reverted");
        balanceInjector.sweepAndCall{value: ethAmount}(address(0), address(targetETH), callData, 4, PLACEHOLDER);
    }

    function testETHPlaceholderReplacement() public {
        uint256 ethAmount = 2.5 ether;

        // Encode calldata with placeholder
        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));

        // Call sweepAndCall with ETH
        balanceInjector.sweepAndCall{value: ethAmount}(address(0), address(targetETH), callData, 4, PLACEHOLDER);

        // Verify the placeholder was correctly replaced with the ETH amount
        assertEq(targetETH.lastAmount(), ethAmount);
        assertEq(targetETH.receivedETH(), ethAmount);
    }

    function testMixedETHAndERC20Operations() public {
        // Test that both ETH and ERC20 operations work independently
        
        // First, test ERC20
        uint256 tokenBalance = 500e18;
        token.mint(address(this), tokenBalance);
        token.approve(address(balanceInjector), tokenBalance);

        bytes memory erc20CallData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));
        balanceInjector.sweepAndCall(address(token), address(target), erc20CallData, 4, PLACEHOLDER);
        assertEq(target.lastAmount(), tokenBalance);

        // Then, test ETH
        uint256 ethAmount = 1.5 ether;
        bytes memory ethCallData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));
        balanceInjector.sweepAndCall{value: ethAmount}(address(0), address(targetETH), ethCallData, 4, PLACEHOLDER);
        assertEq(targetETH.lastAmount(), ethAmount);
        assertEq(targetETH.receivedETH(), ethAmount);
    }

    // Allow test contract to receive ETH for testing
    receive() external payable {}
}
