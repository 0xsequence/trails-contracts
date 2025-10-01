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
    MockERC20 public token;

    constructor(address _token) {
        token = MockERC20(_token);
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function deposit(uint256 amount, address receiver) external {
        if (shouldRevert) revert("Target reverted");
        lastAmount = amount;
        // Pull tokens from msg.sender (simulating real DeFi protocols like Aave)
        if (address(token) != address(0)) {
            token.transferFrom(msg.sender, address(this), amount);
        }
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

/**
 * @dev Mock wallet that delegatecalls BalanceInjector
 * This simulates how Sequence wallets use the contract
 */
contract MockWallet {
    function delegateCallBalanceInjector(
        address balanceInjector,
        address token,
        address target,
        bytes memory callData,
        uint256 amountOffset,
        bytes32 placeholder
    ) external payable returns (bool success, bytes memory result) {
        bytes memory data = abi.encodeWithSignature(
            "injectAndCall(address,address,bytes,uint256,bytes32)",
            token,
            target,
            callData,
            amountOffset,
            placeholder
        );
        return balanceInjector.delegatecall(data);
    }

    function handleSequenceDelegateCall(
        address balanceInjector,
        bytes32 opHash,
        uint256 startingGas,
        uint256 callIndex,
        uint256 numCalls,
        uint256 space,
        bytes memory innerCallData
    ) external payable returns (bool success, bytes memory result) {
        bytes memory data = abi.encodeWithSignature(
            "handleSequenceDelegateCall(bytes32,uint256,uint256,uint256,uint256,bytes)",
            opHash,
            startingGas,
            callIndex,
            numCalls,
            space,
            innerCallData
        );
        return balanceInjector.delegatecall(data);
    }

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
        target = new MockTarget(address(token));
        targetETH = new MockTargetETH();
    }

    // ============ ERC20 Tests ============

    function testInjectSweepAndCall() public {
        // Mint tokens to the caller (this test contract)
        uint256 tokenBalance = 1000e18;
        token.mint(address(this), tokenBalance);

        // Approve balanceInjector to transfer tokens
        token.approve(address(balanceInjector), tokenBalance);

        // Encode calldata with placeholder
        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));

        // Calculate offset (4 bytes for function selector + 0 bytes for first param)
        uint256 amountOffset = 4;

        // Call injectSweepAndCall
        balanceInjector.injectSweepAndCall(address(token), address(target), callData, amountOffset, PLACEHOLDER);

        // Verify target received the correct amount
        assertEq(target.lastAmount(), tokenBalance);

        // Verify tokens were transferred from caller to target (via balanceInjector)
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(target)), tokenBalance);
        assertEq(token.balanceOf(address(balanceInjector)), 0);
        
        // Verify allowance was consumed after transferFrom
        assertEq(token.allowance(address(balanceInjector), address(target)), 0);
    }

    function testRevertWhenNoTokens() public {
        // Don't mint any tokens to the caller
        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));

        vm.expectRevert("No tokens to sweep");
        balanceInjector.injectSweepAndCall(address(token), address(target), callData, 4, PLACEHOLDER);
    }

    function testRevertWhenPlaceholderMismatch() public {
        uint256 tokenBalance = 1000e18;
        token.mint(address(this), tokenBalance);
        token.approve(address(balanceInjector), tokenBalance);

        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));

        bytes32 wrongPlaceholder = 0x1111111111111111111111111111111111111111111111111111111111111111;

        vm.expectRevert("Placeholder mismatch");
        balanceInjector.injectSweepAndCall(address(token), address(target), callData, 4, wrongPlaceholder);
    }

    function testRevertWhenTargetFails() public {
        uint256 tokenBalance = 1000e18;
        token.mint(address(this), tokenBalance);
        token.approve(address(balanceInjector), tokenBalance);
        target.setShouldRevert(true);

        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));

        vm.expectRevert("Target reverted");
        balanceInjector.injectSweepAndCall(address(token), address(target), callData, 4, PLACEHOLDER);
    }

    // ============ ETH Tests ============

    function testSweepAndCallETH() public {
        uint256 ethAmount = 1 ether;

        // Encode calldata with placeholder for ETH
        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));

        // Calculate offset (4 bytes for function selector + 0 bytes for first param)
        uint256 amountOffset = 4;

        // Call injectSweepAndCall with ETH (token = address(0))
        balanceInjector.injectSweepAndCall{value: ethAmount}(address(0), address(targetETH), callData, amountOffset, PLACEHOLDER);

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
        balanceInjector.injectSweepAndCall(address(0), address(targetETH), callData, 4, PLACEHOLDER);
    }

    function testRevertWhenETHPlaceholderMismatch() public {
        uint256 ethAmount = 1 ether;
        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));

        bytes32 wrongPlaceholder = 0x1111111111111111111111111111111111111111111111111111111111111111;

        vm.expectRevert("Placeholder mismatch");
        balanceInjector.injectSweepAndCall{value: ethAmount}(address(0), address(targetETH), callData, 4, wrongPlaceholder);
    }

    function testRevertWhenETHTargetFails() public {
        uint256 ethAmount = 1 ether;
        targetETH.setShouldRevert(true);

        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));

        vm.expectRevert("Target reverted");
        balanceInjector.injectSweepAndCall{value: ethAmount}(address(0), address(targetETH), callData, 4, PLACEHOLDER);
    }

    function testETHPlaceholderReplacement() public {
        uint256 ethAmount = 2.5 ether;

        // Encode calldata with placeholder
        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));

        // Call injectSweepAndCall with ETH
        balanceInjector.injectSweepAndCall{value: ethAmount}(address(0), address(targetETH), callData, 4, PLACEHOLDER);

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
        balanceInjector.injectSweepAndCall(address(token), address(target), erc20CallData, 4, PLACEHOLDER);
        assertEq(target.lastAmount(), tokenBalance);

        // Then, test ETH
        uint256 ethAmount = 1.5 ether;
        bytes memory ethCallData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));
        balanceInjector.injectSweepAndCall{value: ethAmount}(address(0), address(targetETH), ethCallData, 4, PLACEHOLDER);
        assertEq(targetETH.lastAmount(), ethAmount);
        assertEq(targetETH.receivedETH(), ethAmount);
    }

    // Allow test contract to receive ETH for testing
    receive() external payable {}

    // ============ Delegatecall Tests ============

    function testDelegateCallWithETH() public {
        MockWallet wallet = new MockWallet();
        
        // Fund the wallet with ETH
        uint256 ethAmount = 2 ether;
        vm.deal(address(wallet), ethAmount);

        // Encode calldata with placeholder
        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));

        // Delegatecall BalanceInjector from wallet
        // When delegatecalled, BalanceInjector will read address(this).balance (wallet's balance)
        (bool success, ) = wallet.delegateCallBalanceInjector(
            address(balanceInjector),
            address(0), // ETH
            address(targetETH),
            callData,
            4, // offset
            PLACEHOLDER
        );

        assertTrue(success, "Delegatecall should succeed");
        assertEq(targetETH.lastAmount(), ethAmount, "Target should receive wallet's ETH balance");
        assertEq(targetETH.receivedETH(), ethAmount, "Target should receive ETH as msg.value");
        assertEq(address(wallet).balance, 0, "Wallet should be swept empty");
    }

    function testDelegateCallWithERC20() public {
        MockWallet wallet = new MockWallet();
        
        // Mint tokens directly to the wallet
        uint256 tokenBalance = 1000e18;
        token.mint(address(wallet), tokenBalance);

        // Encode calldata with placeholder
        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));

        // Delegatecall BalanceInjector from wallet
        // When delegatecalled, BalanceInjector will read IERC20(token).balanceOf(address(this)) (wallet's balance)
        (bool success, ) = wallet.delegateCallBalanceInjector(
            address(balanceInjector),
            address(token),
            address(target),
            callData,
            4, // offset
            PLACEHOLDER
        );

        assertTrue(success, "Delegatecall should succeed");
        assertEq(target.lastAmount(), tokenBalance, "Target should receive wallet's token balance");
        assertEq(token.balanceOf(address(wallet)), 0, "Wallet tokens should be swept");
    }

    function testHandleSequenceDelegateCall() public {
        MockWallet wallet = new MockWallet();
        
        // Fund the wallet with ETH
        uint256 ethAmount = 1.5 ether;
        vm.deal(address(wallet), ethAmount);

        // Encode the inner injectAndCall
        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));
        bytes memory innerCallData = abi.encodeWithSignature(
            "injectAndCall(address,address,bytes,uint256,bytes32)",
            address(0), // ETH
            address(targetETH),
            callData,
            4, // offset
            PLACEHOLDER
        );

        // Call handleSequenceDelegateCall (simulates Sequence wallet behavior)
        (bool success, ) = wallet.handleSequenceDelegateCall(
            address(balanceInjector),
            bytes32(uint256(1)), // opHash
            1000000, // startingGas
            0, // callIndex
            1, // numCalls
            0, // space
            innerCallData
        );

        assertTrue(success, "handleSequenceDelegateCall should succeed");
        assertEq(targetETH.lastAmount(), ethAmount, "Target should receive ETH");
        assertEq(address(wallet).balance, 0, "Wallet should be swept empty");
    }

    function testHandleSequenceDelegateCallWithERC20() public {
        MockWallet wallet = new MockWallet();
        
        // Mint tokens to wallet
        uint256 tokenBalance = 500e18;
        token.mint(address(wallet), tokenBalance);

        // Encode the inner injectAndCall
        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));
        bytes memory innerCallData = abi.encodeWithSignature(
            "injectAndCall(address,address,bytes,uint256,bytes32)",
            address(token),
            address(target),
            callData,
            4, // offset
            PLACEHOLDER
        );

        // Call handleSequenceDelegateCall
        (bool success, ) = wallet.handleSequenceDelegateCall(
            address(balanceInjector),
            bytes32(uint256(1)), // opHash
            1000000, // startingGas
            0, // callIndex
            1, // numCalls
            0, // space
            innerCallData
        );

        assertTrue(success, "handleSequenceDelegateCall should succeed");
        assertEq(target.lastAmount(), tokenBalance, "Target should receive tokens");
        assertEq(token.balanceOf(address(wallet)), 0, "Wallet tokens should be swept");
    }

    function testSkipPlaceholderReplacementWithZeroOffsetAndPlaceholder() public {
        // Test that when offset=0 and placeholder=0, replacement is skipped
        uint256 ethAmount = 1 ether;
        
        // Calldata without placeholder (direct amount)
        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", ethAmount, address(0x123));

        // Call with offset=0 and placeholder=0 to skip replacement
        balanceInjector.injectSweepAndCall{value: ethAmount}(
            address(0),
            address(targetETH),
            callData,
            0, // offset = 0
            bytes32(0) // placeholder = 0
        );

        // Verify the call succeeded with the original calldata (no replacement)
        assertEq(targetETH.lastAmount(), ethAmount);
        assertEq(targetETH.receivedETH(), ethAmount);
    }

    function testRevertHandleSequenceDelegateCallInvalidSelector() public {
        MockWallet wallet = new MockWallet();
        vm.deal(address(wallet), 1 ether);

        // Encode wrong function (not injectAndCall)
        bytes memory wrongCallData = abi.encodeWithSignature(
            "wrongFunction(address,address)",
            address(0),
            address(targetETH)
        );

        // Should revert with "Invalid selector"
        (bool success, bytes memory result) = wallet.handleSequenceDelegateCall(
            address(balanceInjector),
            bytes32(uint256(1)),
            1000000,
            0,
            1,
            0,
            wrongCallData
        );

        assertFalse(success, "Should fail with invalid selector");
        // Check that it reverted with "Invalid selector"
        bytes memory expectedError = abi.encodeWithSignature("Error(string)", "Invalid selector");
        assertEq(keccak256(result), keccak256(expectedError), "Should revert with 'Invalid selector'");
    }

    function testDelegateCallRevertWhenNoETH() public {
        MockWallet wallet = new MockWallet();
        // Don't fund the wallet (balance = 0)

        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));

        (bool success, ) = wallet.delegateCallBalanceInjector(
            address(balanceInjector),
            address(0),
            address(targetETH),
            callData,
            4,
            PLACEHOLDER
        );

        assertFalse(success, "Should fail when wallet has no ETH");
    }

    function testDelegateCallRevertWhenNoTokens() public {
        MockWallet wallet = new MockWallet();
        // Don't mint tokens to wallet (balance = 0)

        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));

        (bool success, ) = wallet.delegateCallBalanceInjector(
            address(balanceInjector),
            address(token),
            address(target),
            callData,
            4,
            PLACEHOLDER
        );

        assertFalse(success, "Should fail when wallet has no tokens");
    }
}