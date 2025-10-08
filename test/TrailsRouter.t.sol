// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TrailsRouter} from "src/TrailsRouter.sol";
import {MockSenderGetter} from "test/mocks/MockSenderGetter.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockMulticall3} from "test/mocks/MockMulticall3.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IDelegatedExtension} from "wallet-contracts-v3/modules/interfaces/IDelegatedExtension.sol";

// -----------------------------------------------------------------------------
// Helper Contracts and Structs
// -----------------------------------------------------------------------------

// Struct definitions to match the contract's IMulticall3 interface
struct Call3 {
    address target;
    bool allowFailure;
    bytes callData;
}

struct Result {
    bool success;
    bytes returnData;
}

// -----------------------------------------------------------------------------
// Mock Contracts
// -----------------------------------------------------------------------------

// A malicious token for testing transferFrom failures
contract FailingToken is MockERC20 {
    bool public shouldFail;

    constructor() MockERC20("Failing Token", "FAIL", 18) {}

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (shouldFail) {
            return false;
        }
        return super.transferFrom(from, to, amount);
    }
}

// Helper receiver that always reverts on receiving native tokens
contract RevertingReceiver {
    receive() external payable {
        revert("RevertingReceiver: revert on receive");
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

    function deposit(uint256 amount, address /*receiver*/ ) external {
        if (shouldRevert) revert("Target reverted");
        lastAmount = amount;
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

    function depositETH(uint256 amount, address /*receiver*/ ) external payable {
        if (shouldRevert) revert("Target reverted");
        lastAmount = amount;
        receivedETH = msg.value;
    }

    receive() external payable {}
}

contract MockWallet {
    function delegateCallBalanceInjector(
        address router,
        address token,
        address target,
        bytes memory callData,
        uint256 amountOffset,
        bytes32 placeholder
    ) external payable returns (bool success, bytes memory result) {
        bytes memory data = abi.encodeWithSignature(
            "injectAndCall(address,address,bytes,uint256,bytes32)", token, target, callData, amountOffset, placeholder
        );
        return router.delegatecall(data);
    }

    function handleSequenceDelegateCall(
        address router,
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
        return router.delegatecall(data);
    }

    receive() external payable {}
}

// -----------------------------------------------------------------------------
// Test Contract
// -----------------------------------------------------------------------------

contract TrailsRouterTest is Test {
    // -------------------------------------------------------------------------
    // Test State Variables
    // -------------------------------------------------------------------------

    TrailsRouter internal router;
    MockSenderGetter internal getter;
    MockERC20 internal mockToken;
    FailingToken internal failingToken;
    ERC20Mock internal erc20;
    MockTarget internal target;
    MockTargetETH internal targetETH;

    address internal user = makeAddr("user");
    address payable public holder;
    address payable public recipient;

    bytes32 constant PLACEHOLDER = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef;
    bytes32 constant TEST_NAMESPACE = keccak256("org.sequence.trails.router.sentinel");
    bytes32 constant TEST_SUCCESS_VALUE = bytes32(uint256(1));

    // -------------------------------------------------------------------------
    // Events and Errors
    // -------------------------------------------------------------------------

    // Events
    event Sweep(address indexed token, address indexed recipient, uint256 amount);
    event Refund(address indexed token, address indexed recipient, uint256 amount);
    event RefundAndSweep(
        address indexed token,
        address indexed refundRecipient,
        uint256 refundAmount,
        address indexed sweepRecipient,
        uint256 actualRefund,
        uint256 remaining
    );
    event ActualRefund(address indexed token, address indexed recipient, uint256 expected, uint256 actual);
    event BalanceInjectorCall(
        address indexed token,
        address indexed target,
        bytes32 placeholder,
        uint256 amountReplaced,
        uint256 amountOffset,
        bool success,
        bytes result
    );

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        // Deploy mock multicall3 at the expected address
        MockMulticall3 mockMulticall3 = new MockMulticall3();
        vm.etch(0xcA11bde05977b3631167028862bE2a173976CA11, address(mockMulticall3).code);

        router = new TrailsRouter();
        getter = new MockSenderGetter();
        mockToken = new MockERC20("MockToken", "MTK", 18);
        failingToken = new FailingToken();
        erc20 = new ERC20Mock();

        // Create simple MockERC20 for target
        MockERC20 simpleToken = new MockERC20("Simple", "SMP", 18);
        target = new MockTarget(address(simpleToken));
        targetETH = new MockTargetETH();

        holder = payable(address(0xbabe));
        recipient = payable(address(0x1));

        // Install router runtime code at the holder address to simulate delegatecall context
        vm.etch(holder, address(router).code);

        vm.deal(user, 10 ether);
        mockToken.mint(user, 1000e18);
        failingToken.mint(user, 1000e18);
    }

    // -------------------------------------------------------------------------
    // Multicall3 Router Tests
    // -------------------------------------------------------------------------

    function test_Execute_FromEOA_ShouldPreserveEOAAsSender() public {
        address eoa = makeAddr("eoa");

        Call3[] memory calls = new Call3[](1);
        calls[0] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});

        vm.prank(eoa);
        bytes memory callData = abi.encodeWithSignature("aggregate3((address,bool,bytes)[])", calls);
        router.execute(callData);
    }

    function test_Execute_FromContract_ShouldPreserveContractAsSender() public {
        Call3[] memory calls = new Call3[](1);
        calls[0] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});

        bytes memory callData = abi.encodeWithSignature("aggregate3((address,bool,bytes)[])", calls);
        router.execute(callData);
    }

    function test_Execute_WithMultipleCalls() public {
        Call3[] memory calls = new Call3[](2);
        calls[0] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});
        calls[1] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});

        bytes memory callData = abi.encodeWithSignature("aggregate3((address,bool,bytes)[])", calls);
        router.execute(callData);
    }

    function test_pullAmountAndExecute_WithValidToken_ShouldTransferAndExecute() public {
        uint256 transferAmount = 100e18;

        vm.prank(user);
        mockToken.approve(address(router), transferAmount);

        Call3[] memory calls = new Call3[](1);
        calls[0] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});

        bytes memory callData = abi.encodeWithSignature("aggregate3((address,bool,bytes)[])", calls);

        vm.prank(user);
        router.pullAmountAndExecute(address(mockToken), transferAmount, callData);

        assertEq(mockToken.balanceOf(address(router)), transferAmount);
        assertEq(mockToken.balanceOf(user), 1000e18 - transferAmount);
    }

    function test_RevertWhen_pullAmountAndExecute_InsufficientAllowance() public {
        uint256 transferAmount = 100e18;

        Call3[] memory calls = new Call3[](1);
        calls[0] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});

        bytes memory callData = abi.encodeWithSignature("aggregate3((address,bool,bytes)[])", calls);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(router), 0, transferAmount)
        );
        router.pullAmountAndExecute(address(mockToken), transferAmount, callData);
    }

    function test_pullAndExecute_WithValidToken_ShouldTransferFullBalanceAndExecute() public {
        uint256 userBalance = mockToken.balanceOf(user);

        vm.prank(user);
        mockToken.approve(address(router), userBalance);

        Call3[] memory calls = new Call3[](1);
        calls[0] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});

        bytes memory callData = abi.encodeWithSignature("aggregate3((address,bool,bytes)[])", calls);

        vm.prank(user);
        router.pullAndExecute(address(mockToken), callData);

        assertEq(mockToken.balanceOf(address(router)), userBalance);
        assertEq(mockToken.balanceOf(user), 0);
    }

    function test_RevertWhen_pullAndExecute_InsufficientAllowance() public {
        uint256 userBalance = mockToken.balanceOf(user);

        Call3[] memory calls = new Call3[](1);
        calls[0] =
            Call3({target: address(getter), allowFailure: false, callData: abi.encodeWithSignature("getSender()")});

        bytes memory callData = abi.encodeWithSignature("aggregate3((address,bool,bytes)[])", calls);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(router), 0, userBalance)
        );
        router.pullAndExecute(address(mockToken), callData);
    }

    function test_ReceiveETH_ShouldAcceptETH() public {
        uint256 depositAmount = 1 ether;

        vm.prank(user);
        (bool success,) = address(router).call{value: depositAmount}("");
        assertTrue(success);

        assertEq(address(router).balance, depositAmount);
    }

    function test_Multicall3Address_IsCorrect() public view {
        assertEq(router.multicall3(), 0xcA11bde05977b3631167028862bE2a173976CA11);
    }

    // -------------------------------------------------------------------------
    // Balance Injection Tests
    // -------------------------------------------------------------------------

    function testInjectSweepAndCall() public {
        MockERC20 testToken = new MockERC20("Test", "TST", 18);
        MockTarget testTarget = new MockTarget(address(testToken));

        uint256 tokenBalance = 1000e18;
        testToken.mint(address(this), tokenBalance);
        testToken.approve(address(router), tokenBalance);

        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));

        router.injectSweepAndCall(address(testToken), address(testTarget), callData, 4, PLACEHOLDER);

        assertEq(testTarget.lastAmount(), tokenBalance);
        assertEq(testToken.balanceOf(address(this)), 0);
        assertEq(testToken.balanceOf(address(testTarget)), tokenBalance);
    }

    function testSweepAndCallETH() public {
        uint256 ethAmount = 1 ether;

        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));

        router.injectSweepAndCall{value: ethAmount}(address(0), address(targetETH), callData, 4, PLACEHOLDER);

        assertEq(targetETH.lastAmount(), ethAmount);
        assertEq(targetETH.receivedETH(), ethAmount);
        assertEq(address(targetETH).balance, ethAmount);
    }

    function testRevertWhen_injectSweepAndCall_InsufficientAllowance() public {
        uint256 balance = 1e18;
        mockToken.mint(address(this), balance);

        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(router), 0, balance)
        );
        router.injectSweepAndCall(address(mockToken), address(target), callData, 4, PLACEHOLDER);
    }

    function testRevertWhen_injectSweepAndCall_NoEthSent() public {
        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));

        vm.prank(user);
        vm.expectRevert(TrailsRouter.NoEthSent.selector);
        router.injectSweepAndCall{value: 0}(address(0), address(targetETH), callData, 4, PLACEHOLDER);
    }

    function testDelegateCallWithETH() public {
        MockWallet wallet = new MockWallet();

        uint256 ethAmount = 2 ether;
        vm.deal(address(wallet), ethAmount);

        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));

        (bool success,) = wallet.delegateCallBalanceInjector(
            address(router), address(0), address(targetETH), callData, 4, PLACEHOLDER
        );

        assertTrue(success, "Delegatecall should succeed");
        assertEq(targetETH.lastAmount(), ethAmount, "Target should receive wallet's ETH balance");
        assertEq(address(wallet).balance, 0, "Wallet should be swept empty");
    }

    function testRevertWhen_injectAndCall_InsufficientEth() public {
        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));

        vm.prank(holder);
        vm.expectRevert(TrailsRouter.NoEthAvailable.selector);
        TrailsRouter(holder).injectAndCall(address(0), address(targetETH), callData, 4, PLACEHOLDER);
    }

    function testRevertWhen_injectAndCall_NoEthAvailable() public {
        bytes memory callData = abi.encodeWithSignature("depositETH(uint256,address)", PLACEHOLDER, address(0x123));

        vm.expectRevert(TrailsRouter.NoEthAvailable.selector);
        TrailsRouter(holder).injectAndCall(address(0), address(targetETH), callData, 4, PLACEHOLDER);
    }

    // -------------------------------------------------------------------------
    // Token Sweeper Tests
    // -------------------------------------------------------------------------

    function test_sweep_nativeToken() public {
        uint256 amount = 1 ether;
        vm.deal(holder, amount);

        uint256 recipientBalanceBefore = recipient.balance;

        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), recipient, amount);
        TrailsRouter(holder).sweep(address(0), recipient);
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
        TrailsRouter(holder).sweep(address(erc20), recipient);
        uint256 recipientBalanceAfter = erc20.balanceOf(recipient);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, amount);
    }

    function test_refundAndSweep_native_partialRefund() public {
        address refundRecipient = address(0x101);
        address sweepRecipient = address(0x102);

        uint256 amount = 3 ether;
        vm.deal(holder, amount);

        vm.expectEmit(true, true, false, true);
        emit Refund(address(0), refundRecipient, 1 ether);
        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), sweepRecipient, 2 ether);
        vm.expectEmit(true, true, false, true);
        emit RefundAndSweep(address(0), refundRecipient, 1 ether, sweepRecipient, 1 ether, 2 ether);

        TrailsRouter(holder).refundAndSweep(address(0), refundRecipient, 1 ether, sweepRecipient);

        assertEq(holder.balance, 0);
        assertEq(refundRecipient.balance, 1 ether);
        assertEq(sweepRecipient.balance, 2 ether);
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
        vm.expectEmit(true, true, false, true);
        emit RefundAndSweep(address(erc20), refundRecipient, refund, sweepRecipient, refund, amount - refund);

        TrailsRouter(holder).refundAndSweep(address(erc20), refundRecipient, refund, sweepRecipient);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(erc20.balanceOf(refundRecipient), refund);
        assertEq(erc20.balanceOf(sweepRecipient), amount - refund);
    }

    function test_validateOpHashAndSweep_native_success() public {
        bytes32 opHash = keccak256("test-op-hash");
        vm.deal(holder, 1 ether);

        bytes32 slot = keccak256(abi.encode(TEST_NAMESPACE, opHash));
        vm.store(holder, slot, TEST_SUCCESS_VALUE);

        bytes memory data =
            abi.encodeWithSelector(TrailsRouter.validateOpHashAndSweep.selector, bytes32(0), address(0), recipient);

        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), recipient, 1 ether);

        IDelegatedExtension(holder).handleSequenceDelegateCall(opHash, 0, 0, 0, 0, data);

        assertEq(holder.balance, 0);
        assertEq(recipient.balance, 1 ether);
    }

    function test_handleSequenceDelegateCall_dispatches_to_sweep_native() public {
        uint256 amount = 1 ether;
        vm.deal(holder, amount);

        bytes memory data = abi.encodeWithSelector(TrailsRouter.sweep.selector, address(0), recipient);

        vm.expectEmit(true, true, false, true);
        emit Sweep(address(0), recipient, amount);

        IDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);

        assertEq(holder.balance, 0);
        assertEq(recipient.balance, amount);
    }

    function test_handleSequenceDelegateCall_invalid_selector_reverts() public {
        bytes memory data = hex"deadbeef";

        vm.expectRevert(abi.encodeWithSelector(TrailsRouter.InvalidDelegatedSelector.selector, bytes4(0xdeadbeef)));
        IDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);
    }

    function test_direct_sweep_reverts_not_delegatecall() public {
        vm.expectRevert(TrailsRouter.NotDelegateCall.selector);
        router.sweep(address(0), recipient);
    }

    function test_native_transfer_failed() public {
        RevertingReceiver revertingReceiver = new RevertingReceiver();

        // Give holder some ETH to sweep
        vm.deal(holder, 1 ether);

        // Verify holder has ETH
        assertEq(holder.balance, 1 ether);

        vm.expectRevert(TrailsRouter.NativeTransferFailed.selector);
        // Call sweep through holder to simulate delegatecall context
        holder.call(abi.encodeWithSelector(router.sweep.selector, address(0), address(revertingReceiver)));
    }

    function test_success_sentinel_not_set() public {
        bytes32 opHash = keccak256("test operation");
        address token = address(mockToken);
        address recipientAddr = recipient;

        vm.expectRevert(TrailsRouter.SuccessSentinelNotSet.selector);
        // Call through holder to simulate delegatecall context
        holder.call(abi.encodeWithSelector(router.validateOpHashAndSweep.selector, opHash, token, recipientAddr));
    }

    function test_no_tokens_to_pull() public {
        address token = address(new MockERC20("Test", "TST", 18)); // New token, caller has 0 balance
        bytes memory callData = abi.encodeWithSelector(bytes4(0x12345678)); // Dummy selector

        vm.expectRevert(TrailsRouter.NoTokensToPull.selector);
        router.pullAndExecute(token, callData);
    }

    function test_no_tokens_to_sweep() public {
        address token = address(new MockERC20("Test", "TST", 18)); // New token, contract has 0 balance
        MockTarget mockTarget = new MockTarget(address(token));
        bytes memory callData = abi.encodeWithSelector(mockTarget.deposit.selector, 100, address(0));

        vm.expectRevert(TrailsRouter.NoTokensToSweep.selector);
        // Call through holder to simulate delegatecall context
        holder.call(
            abi.encodeWithSelector(router.injectAndCall.selector, token, address(mockTarget), callData, 0, bytes32(0))
        );
    }

    function test_amount_offset_out_of_bounds() public {
        MockTarget mockTarget = new MockTarget(address(mockToken));
        // Create callData that's too short for the amountOffset
        bytes memory callData = hex"12345678"; // 4 bytes, less than amountOffset + 32 = 36 + 32 = 68
        uint256 amountOffset = 36; // This will make amountOffset + 32 = 68 > callData.length

        vm.expectRevert(TrailsRouter.AmountOffsetOutOfBounds.selector);
        // Call through holder to simulate delegatecall context
        holder.call(
            abi.encodeWithSelector(
                router.injectAndCall.selector,
                address(mockToken),
                address(mockTarget),
                callData,
                amountOffset,
                bytes32(uint256(0xdeadbeef))
            )
        );
    }

    function test_placeholder_mismatch() public {
        MockTarget mockTarget = new MockTarget(address(mockToken));
        // Create callData with wrong placeholder
        bytes32 wrongPlaceholder = bytes32(uint256(0x12345678));
        bytes32 expectedPlaceholder = bytes32(uint256(0xdeadbeef));
        bytes memory callData = abi.encodeWithSelector(mockTarget.deposit.selector, wrongPlaceholder, address(0));

        vm.expectRevert(TrailsRouter.PlaceholderMismatch.selector);
        // Call through holder to simulate delegatecall context
        holder.call(
            abi.encodeWithSelector(
                router.injectAndCall.selector, address(mockToken), address(mockTarget), callData, 4, expectedPlaceholder
            )
        );
    }

    function trailsRouterHelperInjectAndCall(
        address token,
        address targetAddress,
        bytes memory callData,
        uint256 amountOffset,
        bytes32 placeholder,
        uint256 ethBalance
    ) internal {
        address wallet = address(0xcafe);
        vm.etch(wallet, address(router).code);
        vm.deal(wallet, ethBalance);
        vm.expectCall(targetAddress, ethBalance, callData);
        (bool success,) = wallet.call(
            abi.encodeWithSignature(
                "injectAndCall(address,address,bytes,uint256,bytes32)",
                token,
                targetAddress,
                callData,
                amountOffset,
                placeholder
            )
        );
        vm.assertEq(success, false, "helper should bubble revert for assertions");
    }
}
