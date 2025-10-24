// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TrailsRouter} from "src/TrailsRouter.sol";
import {DelegatecallGuard} from "src/guards/DelegatecallGuard.sol";
import {MockSenderGetter} from "test/mocks/MockSenderGetter.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockMulticall3} from "test/mocks/MockMulticall3.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IDelegatedExtension} from "wallet-contracts-v3/modules/interfaces/IDelegatedExtension.sol";
import {TstoreSetter, TstoreMode, TstoreRead} from "test/utils/TstoreUtils.sol";
import {TrailsSentinelLib} from "src/libraries/TrailsSentinelLib.sol";
import {IMulticall3} from "src/interfaces/IMulticall3.sol";

// -----------------------------------------------------------------------------
// Helper Contracts and Structs
// -----------------------------------------------------------------------------

// Use IMulticall3.Result directly

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

    function deposit(
        uint256 amount,
        address /*receiver*/
    )
        external
    {
        if (shouldRevert) revert("Target reverted");
        lastAmount = amount;
        if (address(token) != address(0)) {
            require(token.transferFrom(msg.sender, address(this), amount), "ERC20 transferFrom failed");
        }
    }
}

contract MockTargetETH {
    uint256 public lastAmount;
    uint256 public receivedEth;
    bool public shouldRevert;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function depositEth(
        uint256 amount,
        address /*receiver*/
    )
        external
        payable
    {
        if (shouldRevert) revert("Target reverted");
        lastAmount = amount;
        receivedEth = msg.value;
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
    MockTargetETH internal targetEth;

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
        targetEth = new MockTargetETH();

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

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        vm.prank(eoa);
        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);
        router.execute(callData);
    }

    function test_Execute_FromContract_ShouldPreserveContractAsSender() public {
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);
        router.execute(callData);
    }

    function test_Execute_WithMultipleCalls() public {
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](2);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });
        calls[1] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);
        router.execute(callData);
    }

    function test_pullAmountAndExecute_WithValidToken_ShouldTransferAndExecute() public {
        uint256 transferAmount = 100e18;

        vm.prank(user);
        mockToken.approve(address(router), transferAmount);

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        vm.prank(user);
        router.pullAmountAndExecute(address(mockToken), transferAmount, callData);

        assertEq(mockToken.balanceOf(address(router)), transferAmount);
        assertEq(mockToken.balanceOf(user), 1000e18 - transferAmount);
    }

    function test_RevertWhen_pullAmountAndExecute_InsufficientAllowance() public {
        uint256 transferAmount = 100e18;

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

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

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        vm.prank(user);
        router.pullAndExecute(address(mockToken), callData);

        assertEq(mockToken.balanceOf(address(router)), userBalance);
        assertEq(mockToken.balanceOf(user), 0);
    }

    function test_RevertWhen_pullAndExecute_InsufficientAllowance() public {
        uint256 userBalance = mockToken.balanceOf(user);

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

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
        assertEq(router.MULTICALL3(), 0xcA11bde05977b3631167028862bE2a173976CA11);
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

        bytes memory callData = abi.encodeWithSignature("depositEth(uint256,address)", PLACEHOLDER, address(0x123));

        router.injectSweepAndCall{value: ethAmount}(address(0), address(targetEth), callData, 4, PLACEHOLDER);

        assertEq(targetEth.lastAmount(), ethAmount);
        assertEq(targetEth.receivedEth(), ethAmount);
        assertEq(address(targetEth).balance, ethAmount);
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
        bytes memory callData = abi.encodeWithSignature("depositEth(uint256,address)", PLACEHOLDER, address(0x123));

        vm.prank(user);
        vm.expectRevert(TrailsRouter.NoEthSent.selector);
        router.injectSweepAndCall{value: 0}(address(0), address(targetEth), callData, 4, PLACEHOLDER);
    }

    function testDelegateCallWithETH() public {
        MockWallet wallet = new MockWallet();

        uint256 ethAmount = 2 ether;
        vm.deal(address(wallet), ethAmount);

        bytes memory callData = abi.encodeWithSignature("depositEth(uint256,address)", PLACEHOLDER, address(0x123));

        (bool success,) = wallet.delegateCallBalanceInjector(
            address(router), address(0), address(targetEth), callData, 4, PLACEHOLDER
        );

        assertTrue(success, "Delegatecall should succeed");
        assertEq(targetEth.lastAmount(), ethAmount, "Target should receive wallet's ETH balance");
        assertEq(address(wallet).balance, 0, "Wallet should be swept empty");
    }

    function testRevertWhen_injectAndCall_InsufficientEth() public {
        bytes memory callData = abi.encodeWithSignature("depositEth(uint256,address)", PLACEHOLDER, address(0x123));

        vm.prank(holder);
        vm.expectRevert(TrailsRouter.NoEthAvailable.selector);
        TrailsRouter(holder).injectAndCall(address(0), address(targetEth), callData, 4, PLACEHOLDER);
    }

    function testRevertWhen_injectAndCall_NoEthAvailable() public {
        bytes memory callData = abi.encodeWithSignature("depositEth(uint256,address)", PLACEHOLDER, address(0x123));

        vm.expectRevert(TrailsRouter.NoEthAvailable.selector);
        TrailsRouter(holder).injectAndCall(address(0), address(targetEth), callData, 4, PLACEHOLDER);
    }

    // -------------------------------------------------------------------------
    // Token Sweeper Tests
    // -------------------------------------------------------------------------

    function test_sweep_nativeToken() public {
        uint256 amount = 1 ether;
        vm.deal(holder, amount);

        uint256 recipientBalanceBefore = recipient.balance;

        vm.expectEmit(true, true, false, false);
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

        vm.expectEmit(true, true, false, false);
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

        vm.expectEmit(true, true, false, false);
        emit Refund(address(0), refundRecipient, 1 ether);
        vm.expectEmit(true, true, false, false);
        emit Sweep(address(0), sweepRecipient, 2 ether);
        vm.expectEmit(true, true, false, false);
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

        vm.expectEmit(true, true, false, false);
        emit Refund(address(erc20), refundRecipient, refund);
        vm.expectEmit(true, true, false, false);
        emit Sweep(address(erc20), sweepRecipient, amount - refund);
        vm.expectEmit(true, true, false, false);
        emit RefundAndSweep(address(erc20), refundRecipient, refund, sweepRecipient, refund, amount - refund);

        TrailsRouter(holder).refundAndSweep(address(erc20), refundRecipient, refund, sweepRecipient);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(erc20.balanceOf(refundRecipient), refund);
        assertEq(erc20.balanceOf(sweepRecipient), amount - refund);
    }

    function test_validateOpHashAndSweep_native_success() public {
        // Force tstore active for delegated storage context (holder)
        TstoreMode.setActive(holder);

        bytes32 opHash = keccak256("test-op-hash");
        vm.deal(holder, 1 ether);

        // Compute slot using the same logic as TrailsSentinelLib.successSlot
        bytes32 namespace = TEST_NAMESPACE;
        bytes32 slot;
        assembly {
            mstore(0x00, namespace)
            mstore(0x20, opHash)
            slot := keccak256(0x00, 0x40)
        }

        // Set transient storage inline at holder's context using bytecode deployment
        // tstore(slot, value) - slot must be on top of stack
        bytes memory setTstoreCode = abi.encodePacked(
            hex"7f",
            TEST_SUCCESS_VALUE, // push32 value
            hex"7f",
            slot, // push32 slot (on top)
            hex"5d", // tstore(slot, value)
            hex"00" // stop
        );

        bytes memory routerCode = address(router).code;
        vm.etch(holder, setTstoreCode);
        (bool ok,) = holder.call("");
        assertTrue(ok, "tstore set failed");
        vm.etch(holder, routerCode);

        bytes memory data =
            abi.encodeWithSelector(TrailsRouter.validateOpHashAndSweep.selector, bytes32(0), address(0), recipient);
        vm.expectEmit(true, true, false, false);
        emit Sweep(address(0), recipient, 1 ether);
        IDelegatedExtension(holder).handleSequenceDelegateCall(opHash, 0, 0, 0, 0, data);

        assertEq(holder.balance, 0);
        assertEq(recipient.balance, 1 ether);
    }

    function test_validateOpHashAndSweep_native_success_tstore() public {
        // Force tstore active for delegated storage context (holder)
        TstoreMode.setActive(holder);

        // Arrange
        bytes32 opHash = keccak256("test-op-hash-tstore");
        vm.deal(holder, 1 ether);

        // Pre-write success sentinel using tstore at the delegated storage of `holder`.
        bytes32 slot = keccak256(abi.encode(TEST_NAMESPACE, opHash));
        bytes memory routerCode = address(router).code;
        vm.etch(holder, address(new TstoreSetter()).code);
        (bool ok,) = holder.call(abi.encodeWithSelector(TstoreSetter.set.selector, slot, TEST_SUCCESS_VALUE));
        assertTrue(ok, "tstore set failed");
        vm.etch(holder, routerCode);

        // Act via delegated entrypoint
        bytes memory data =
            abi.encodeWithSelector(TrailsRouter.validateOpHashAndSweep.selector, bytes32(0), address(0), recipient);
        vm.expectEmit(true, true, false, false);
        emit Sweep(address(0), recipient, 1 ether);
        IDelegatedExtension(holder).handleSequenceDelegateCall(opHash, 0, 0, 0, 0, data);

        // Assert: with tstore active, the sstore slot should remain zero
        uint256 storedS = uint256(vm.load(holder, slot));
        assertEq(storedS, 0);
        assertEq(holder.balance, 0);
        assertEq(recipient.balance, 1 ether);

        // Read via tload
        slot = bytes32(TrailsSentinelLib.successSlot(opHash));
        uint256 storedT = TstoreRead.tloadAt(holder, slot);
        assertEq(storedT, TrailsSentinelLib.SUCCESS_VALUE);
    }

    function test_handleSequenceDelegateCall_dispatches_to_sweep_native() public {
        uint256 amount = 1 ether;
        vm.deal(holder, amount);

        bytes memory data = abi.encodeWithSelector(TrailsRouter.sweep.selector, address(0), recipient);

        vm.expectEmit(true, true, false, false);
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
        vm.expectRevert(DelegatecallGuard.NotDelegateCall.selector);
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
        (bool success,) =
            holder.call(abi.encodeWithSelector(router.sweep.selector, address(0), address(revertingReceiver)));
        success;
    }

    function test_success_sentinel_not_set() public {
        bytes32 opHash = keccak256("test operation");
        address token = address(mockToken);
        address recipientAddr = recipient;

        vm.expectRevert(TrailsRouter.SuccessSentinelNotSet.selector);
        // Call through holder to simulate delegatecall context
        (bool success,) =
            holder.call(abi.encodeWithSelector(router.validateOpHashAndSweep.selector, opHash, token, recipientAddr));
        success;
    }

    function test_no_tokens_to_pull() public {
        address token = address(new MockERC20("Test", "TST", 18)); // New token, caller has 0 balance

        // Use a valid aggregate3Value call so selector validation passes and we hit NoTokensToPull
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });
        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        vm.expectRevert(TrailsRouter.NoTokensToPull.selector);
        router.pullAndExecute(token, callData);
    }

    function test_no_tokens_to_sweep() public {
        address token = address(new MockERC20("Test", "TST", 18)); // New token, contract has 0 balance
        MockTarget mockTarget = new MockTarget(address(token));
        bytes memory callData = abi.encodeWithSelector(mockTarget.deposit.selector, 100, address(0));

        vm.expectRevert(TrailsRouter.NoTokensToSweep.selector);
        // Call through holder to simulate delegatecall context
        (bool success,) = holder.call(
            abi.encodeWithSelector(router.injectAndCall.selector, token, address(mockTarget), callData, 0, bytes32(0))
        );
        success;
    }

    function test_amount_offset_out_of_bounds() public {
        MockTarget mockTarget = new MockTarget(address(mockToken));
        // Create callData that's too short for the amountOffset
        bytes memory callData = hex"12345678"; // 4 bytes, less than amountOffset + 32 = 36 + 32 = 68
        uint256 amountOffset = 36; // This will make amountOffset + 32 = 68 > callData.length

        vm.expectRevert(TrailsRouter.AmountOffsetOutOfBounds.selector);
        // Call through holder to simulate delegatecall context
        (bool success,) = holder.call(
            abi.encodeWithSelector(
                router.injectAndCall.selector,
                address(mockToken),
                address(mockTarget),
                callData,
                amountOffset,
                bytes32(uint256(0xdeadbeef))
            )
        );
        success;
    }

    function test_placeholder_mismatch() public {
        MockTarget mockTarget = new MockTarget(address(mockToken));
        // Create callData with wrong placeholder
        bytes32 wrongPlaceholder = bytes32(uint256(0x12345678));
        bytes32 expectedPlaceholder = bytes32(uint256(0xdeadbeef));
        bytes memory callData = abi.encodeWithSelector(mockTarget.deposit.selector, wrongPlaceholder, address(0));

        vm.expectRevert(TrailsRouter.PlaceholderMismatch.selector);
        // Call through holder to simulate delegatecall context
        (bool success,) = holder.call(
            abi.encodeWithSelector(
                router.injectAndCall.selector, address(mockToken), address(mockTarget), callData, 4, expectedPlaceholder
            )
        );
        success;
    }

    function test_pullAndExecute_WithETH_ShouldTransferAndExecute() public {
        uint256 ethAmount = 1 ether;
        vm.deal(user, ethAmount);

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        vm.prank(user);
        router.pullAndExecute{value: ethAmount}(address(0), callData);

        assertEq(address(router).balance, ethAmount);
        assertEq(user.balance, 0);
    }

    function test_pullAndExecute_WithETH_NoEthSent() public {
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        vm.prank(user);
        vm.expectRevert(TrailsRouter.NoEthSent.selector);
        router.pullAndExecute(address(0), callData);
    }

    function test_pullAmountAndExecute_WithETH_ShouldTransferAndExecute() public {
        uint256 ethAmount = 1 ether;
        vm.deal(user, ethAmount);

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        vm.prank(user);
        router.pullAmountAndExecute{value: ethAmount}(address(0), ethAmount, callData);

        assertEq(address(router).balance, ethAmount);
        assertEq(user.balance, 0);
    }

    function test_pullAmountAndExecute_WithETH_InsufficientEthSent() public {
        uint256 requiredAmount = 1 ether;
        uint256 sentAmount = 0.5 ether;

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(TrailsRouter.InsufficientEth.selector, requiredAmount, sentAmount));
        router.pullAmountAndExecute{value: sentAmount}(address(0), requiredAmount, callData);
    }

    function test_pullAmountAndExecute_WithToken_ShouldTransferAndExecute() public {
        uint256 transferAmount = 100e18;

        vm.prank(user);
        mockToken.approve(address(router), transferAmount);

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        vm.prank(user);
        router.pullAmountAndExecute(address(mockToken), transferAmount, callData);

        assertEq(mockToken.balanceOf(address(router)), transferAmount);
        assertEq(mockToken.balanceOf(user), 1000e18 - transferAmount);
    }

    function testExecute_WithFailingMulticall() public {
        // Save original multicall code
        bytes memory originalCode = 0xcA11bde05977b3631167028862bE2a173976CA11.code;

        // Deploy and etch failing multicall
        MockMulticall3 failingMulticall = new MockMulticall3();
        vm.etch(0xcA11bde05977b3631167028862bE2a173976CA11, address(failingMulticall).code);

        // Verify the etch worked
        assertEq(keccak256(0xcA11bde05977b3631167028862bE2a173976CA11.code), keccak256(address(failingMulticall).code));

        // Set the failure flag directly in storage since delegatecall uses caller's storage
        // The shouldFail variable is at slot 0 in MockMulticall3
        vm.store(address(router), bytes32(0), bytes32(uint256(1))); // Set shouldFail = true in router's storage

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        vm.expectRevert(
            abi.encodeWithSelector(
                TrailsRouter.TargetCallFailed.selector,
                abi.encodeWithSignature("Error(string)", "MockMulticall3: forced failure")
            )
        );
        router.execute(callData);

        // Restore original code
        vm.etch(0xcA11bde05977b3631167028862bE2a173976CA11, originalCode);
    }

    function test_pullAndExecute_WithFailingMulticall() public {
        uint256 transferAmount = 100e18;

        // Save original multicall code
        bytes memory originalCode = 0xcA11bde05977b3631167028862bE2a173976CA11.code;

        // Mock multicall3 to return failure
        MockMulticall3 failingMulticall = new MockMulticall3();
        vm.etch(0xcA11bde05977b3631167028862bE2a173976CA11, address(failingMulticall).code);

        // Set the failure flag directly in storage since delegatecall uses caller's storage
        vm.store(address(router), bytes32(0), bytes32(uint256(1))); // Set shouldFail = true in router's storage

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        // Give tokens to the test contract (which will be msg.sender) and approve
        mockToken.mint(address(this), transferAmount);
        mockToken.approve(address(router), transferAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                TrailsRouter.TargetCallFailed.selector,
                abi.encodeWithSignature("Error(string)", "MockMulticall3: forced failure")
            )
        );
        router.pullAndExecute(address(mockToken), callData);

        // Restore original code
        vm.etch(0xcA11bde05977b3631167028862bE2a173976CA11, originalCode);
    }

    function testInjectSweepAndCall_WithETH_ZeroBalance() public {
        bytes memory callData = abi.encodeWithSignature("depositEth(uint256,address)", PLACEHOLDER, address(0x123));

        vm.expectRevert(TrailsRouter.NoEthSent.selector);
        router.injectSweepAndCall{value: 0}(address(0), address(targetEth), callData, 4, PLACEHOLDER);
    }

    function testInjectSweepAndCall_WithToken_ZeroBalance() public {
        MockERC20 zeroToken = new MockERC20("Zero", "ZERO", 18);
        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0));

        vm.expectRevert(TrailsRouter.NoTokensToSweep.selector);
        router.injectSweepAndCall(address(zeroToken), address(target), callData, 4, PLACEHOLDER);
    }

    function testInjectAndCall_WithZeroBalance() public {
        bytes memory callData = abi.encodeWithSignature("depositEth(uint256,address)", PLACEHOLDER, address(0x123));

        vm.prank(holder);
        vm.expectRevert(TrailsRouter.NoEthAvailable.selector);
        TrailsRouter(holder).injectAndCall(address(0), address(targetEth), callData, 4, PLACEHOLDER);
    }

    function testInjectAndCall_WithTokenZeroBalance() public {
        MockERC20 zeroToken = new MockERC20("Zero", "ZERO", 18);
        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0));

        vm.prank(holder);
        vm.expectRevert(TrailsRouter.NoTokensToSweep.selector);
        TrailsRouter(holder).injectAndCall(address(zeroToken), address(target), callData, 4, PLACEHOLDER);
    }

    function testInjectSweepAndCall_WithETH_TargetCallFails() public {
        uint256 ethAmount = 1 ether;

        bytes memory callData = abi.encodeWithSignature("depositEth(uint256,address)", PLACEHOLDER, address(0x123));

        // Make target revert
        targetEth.setShouldRevert(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                TrailsRouter.TargetCallFailed.selector, abi.encodeWithSignature("Error(string)", "Target reverted")
            )
        );
        router.injectSweepAndCall{value: ethAmount}(address(0), address(targetEth), callData, 4, PLACEHOLDER);
    }

    function testInjectSweepAndCall_WithToken_TargetCallFails() public {
        MockERC20 testToken = new MockERC20("Test", "TST", 18);
        MockTarget testTarget = new MockTarget(address(testToken));

        uint256 tokenBalance = 1000e18;
        testToken.mint(address(this), tokenBalance);
        testToken.approve(address(router), tokenBalance);

        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));

        // Make target revert
        testTarget.setShouldRevert(true);

        vm.expectRevert(
            abi.encodeWithSelector(
                TrailsRouter.TargetCallFailed.selector, abi.encodeWithSignature("Error(string)", "Target reverted")
            )
        );
        router.injectSweepAndCall(address(testToken), address(testTarget), callData, 4, PLACEHOLDER);
    }

    function testRefundAndSweep_FullRefund() public {
        address refundRecipient = address(0x201);
        address sweepRecipient = address(0x202);

        uint256 amount = 3 ether;
        vm.deal(holder, amount);

        vm.expectEmit(true, true, false, false);
        emit Refund(address(0), refundRecipient, amount);
        vm.expectEmit(true, true, false, false);
        emit RefundAndSweep(address(0), refundRecipient, amount, sweepRecipient, amount, 0);

        TrailsRouter(holder).refundAndSweep(address(0), refundRecipient, amount, sweepRecipient);

        assertEq(holder.balance, 0);
        assertEq(refundRecipient.balance, amount);
        assertEq(sweepRecipient.balance, 0);
    }

    function testRefundAndSweep_PartialRefundERC20() public {
        address refundRecipient = address(0x301);
        address sweepRecipient = address(0x302);

        uint256 amount = 300 * 1e18;
        uint256 refundRequested = 400 * 1e18; // More than available
        erc20.mint(holder, amount);

        vm.expectEmit(true, true, false, false);
        emit ActualRefund(address(erc20), refundRecipient, refundRequested, amount);
        vm.expectEmit(true, true, false, false);
        emit Refund(address(erc20), refundRecipient, amount); // Refund full amount available
        vm.expectEmit(true, true, false, false);
        emit RefundAndSweep(address(erc20), refundRecipient, refundRequested, sweepRecipient, amount, 0);

        TrailsRouter(holder).refundAndSweep(address(erc20), refundRecipient, refundRequested, sweepRecipient);

        assertEq(erc20.balanceOf(holder), 0);
        assertEq(erc20.balanceOf(refundRecipient), amount);
        assertEq(erc20.balanceOf(sweepRecipient), 0);
    }

    function testRefundAndSweep_ZeroRefundAmount() public {
        address refundRecipient = address(0x401);
        address sweepRecipient = address(0x402);

        uint256 amount = 3 ether;
        uint256 refundRequested = 0;
        vm.deal(holder, amount);

        vm.expectEmit(true, true, false, false);
        emit Sweep(address(0), sweepRecipient, amount);
        vm.expectEmit(true, true, false, false);
        emit RefundAndSweep(address(0), refundRecipient, refundRequested, sweepRecipient, 0, amount);

        TrailsRouter(holder).refundAndSweep(address(0), refundRecipient, refundRequested, sweepRecipient);

        assertEq(holder.balance, 0);
        assertEq(refundRecipient.balance, 0);
        assertEq(sweepRecipient.balance, amount);
    }

    function testValidateOpHashAndSweep_WithoutSentinel() public {
        bytes32 opHash = keccak256("test operation without sentinel");
        address token = address(mockToken);
        address recipientAddr = recipient;

        vm.expectRevert(TrailsRouter.SuccessSentinelNotSet.selector);
        // Call through holder to simulate delegatecall context
        (bool success,) =
            holder.call(abi.encodeWithSelector(router.validateOpHashAndSweep.selector, opHash, token, recipientAddr));
        success;
    }

    function testHandleSequenceDelegateCall_InjectAndCall() public {
        uint256 ethAmount = 1 ether;
        vm.deal(holder, ethAmount);

        bytes memory callData = abi.encodeWithSignature("depositEth(uint256,address)", PLACEHOLDER, address(0x123));
        bytes memory innerData = abi.encodeWithSelector(
            router.injectAndCall.selector, address(0), address(targetEth), callData, uint256(4), PLACEHOLDER
        );

        IDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, innerData);

        assertEq(holder.balance, 0);
        assertEq(address(targetEth).balance, ethAmount);
        assertEq(targetEth.lastAmount(), ethAmount);
    }

    function testHandleSequenceDelegateCall_Sweep() public {
        uint256 amount = 1 ether;
        vm.deal(holder, amount);

        bytes memory innerData = abi.encodeWithSelector(router.sweep.selector, address(0), recipient);

        IDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, innerData);

        assertEq(holder.balance, 0);
        assertEq(recipient.balance, amount);
    }

    function testHandleSequenceDelegateCall_RefundAndSweep() public {
        address refundRecipient = address(0x501);
        address sweepRecipient = address(0x502);

        uint256 amount = 3 ether;
        vm.deal(holder, amount);

        bytes memory innerData = abi.encodeWithSelector(
            router.refundAndSweep.selector, address(0), refundRecipient, uint256(1 ether), sweepRecipient
        );

        IDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, innerData);

        assertEq(holder.balance, 0);
        assertEq(refundRecipient.balance, 1 ether);
        assertEq(sweepRecipient.balance, 2 ether);
    }

    function testHandleSequenceDelegateCall_ValidateOpHashAndSweep() public {
        // Force tstore active for delegated storage context (holder)
        TstoreMode.setActive(holder);

        bytes32 opHash = keccak256("test-op-hash-delegated");
        vm.deal(holder, 1 ether);

        // Set sentinel
        bytes32 slot = keccak256(abi.encode(TEST_NAMESPACE, opHash));
        bytes memory setTstoreCode = abi.encodePacked(hex"7f", TEST_SUCCESS_VALUE, hex"7f", slot, hex"5d", hex"00");

        bytes memory routerCode = address(router).code;
        vm.etch(holder, setTstoreCode);
        (bool ok,) = holder.call("");
        assertTrue(ok, "tstore set failed");
        vm.etch(holder, routerCode);

        bytes memory innerData =
            abi.encodeWithSelector(router.validateOpHashAndSweep.selector, bytes32(0), address(0), recipient);

        IDelegatedExtension(holder).handleSequenceDelegateCall(opHash, 0, 0, 0, 0, innerData);

        assertEq(holder.balance, 0);
        assertEq(recipient.balance, 1 ether);
    }

    function testInjectAndCall_NoReplacementNeeded() public {
        MockERC20 testToken = new MockERC20("Test", "TST", 18);
        MockTarget testTarget = new MockTarget(address(testToken));

        uint256 tokenBalance = 1000e18;
        testToken.mint(holder, tokenBalance);

        // Call data with placeholder at offset 4 (after selector)
        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));
        uint256 amountOffset = 4; // Offset to the uint256 parameter
        bytes32 placeholder = PLACEHOLDER;

        // Event is emitted during the call

        TrailsRouter(holder).injectAndCall(address(testToken), address(testTarget), callData, amountOffset, placeholder);

        assertEq(testTarget.lastAmount(), tokenBalance); // Should use the replaced value
        assertEq(testToken.balanceOf(holder), 0);
        assertEq(testToken.balanceOf(address(testTarget)), tokenBalance);
    }

    function testInjectAndCall_WithReplacement() public {
        MockERC20 testToken = new MockERC20("Test", "TST", 18);
        MockTarget testTarget = new MockTarget(address(testToken));

        uint256 tokenBalance = 1000e18;
        testToken.mint(holder, tokenBalance);

        bytes memory callData = abi.encodeWithSignature("deposit(uint256,address)", PLACEHOLDER, address(0x123));
        uint256 amountOffset = 4;
        bytes32 placeholder = PLACEHOLDER;

        vm.expectEmit(true, true, false, false);
        emit BalanceInjectorCall(
            address(testToken), address(testTarget), placeholder, tokenBalance, amountOffset, true, ""
        );

        TrailsRouter(holder).injectAndCall(address(testToken), address(testTarget), callData, amountOffset, placeholder);

        assertEq(testTarget.lastAmount(), tokenBalance);
        assertEq(testToken.balanceOf(holder), 0);
        assertEq(testToken.balanceOf(address(testTarget)), tokenBalance);
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

    function testNativeTransferFailure() public {
        RevertingReceiver revertingReceiver = new RevertingReceiver();

        vm.deal(holder, 1 ether);

        // This should exercise the _transferNative function and cause NativeTransferFailed
        vm.expectRevert(TrailsRouter.NativeTransferFailed.selector);
        TrailsRouter(holder).sweep(address(0), address(revertingReceiver));
    }

    function testInsufficientEthValidation() public {
        uint256 requiredAmount = 2 ether;
        uint256 sentAmount = 1 ether;

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        vm.expectRevert(abi.encodeWithSelector(TrailsRouter.InsufficientEth.selector, requiredAmount, sentAmount));
        router.pullAmountAndExecute{value: sentAmount}(address(0), requiredAmount, callData);
    }

    // =========================================================================
    // SEQ-3: AllowFailure Validation Tests
    // =========================================================================

    /**
     * @notice Test that pullAmountAndExecute reverts when allowFailure is true for a single call
     * @dev Validates the fix for SEQ-3 - preventing silent execution failures
     */
    function test_RevertWhen_allowFailure_true_singleCall() public {
        erc20.mint(user, 100 ether);
        vm.startPrank(user);
        erc20.approve(address(router), 100 ether);

        // Create a call with allowFailure=true (should be rejected)
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter),
            allowFailure: true, // This should cause revert
            value: 0,
            callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        // Should revert with AllowFailureMustBeFalse error for index 0
        vm.expectRevert(abi.encodeWithSelector(TrailsRouter.AllowFailureMustBeFalse.selector, 0));
        router.pullAmountAndExecute(address(erc20), 10 ether, callData);

        vm.stopPrank();
    }

    /**
     * @notice Test that pullAmountAndExecute reverts when allowFailure is true in the first of multiple calls
     * @dev Verifies that validation catches allowFailure=true at index 0
     */
    function test_RevertWhen_allowFailure_true_firstOfMultipleCalls() public {
        erc20.mint(user, 100 ether);
        vm.startPrank(user);
        erc20.approve(address(router), 100 ether);

        // Create multiple calls where the first one has allowFailure=true
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](3);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter),
            allowFailure: true, // This should cause revert
            value: 0,
            callData: abi.encodeWithSignature("getSender()")
        });
        calls[1] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });
        calls[2] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        // Should revert with AllowFailureMustBeFalse error for index 0
        vm.expectRevert(abi.encodeWithSelector(TrailsRouter.AllowFailureMustBeFalse.selector, 0));
        router.pullAmountAndExecute(address(erc20), 10 ether, callData);

        vm.stopPrank();
    }

    /**
     * @notice Test that pullAmountAndExecute reverts when allowFailure is true in the middle of multiple calls
     * @dev Verifies that validation catches allowFailure=true at index 1
     */
    function test_RevertWhen_allowFailure_true_middleOfMultipleCalls() public {
        erc20.mint(user, 100 ether);
        vm.startPrank(user);
        erc20.approve(address(router), 100 ether);

        // Create multiple calls where the second one has allowFailure=true
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](3);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });
        calls[1] = IMulticall3.Call3Value({
            target: address(getter),
            allowFailure: true, // This should cause revert
            value: 0,
            callData: abi.encodeWithSignature("getSender()")
        });
        calls[2] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        // Should revert with AllowFailureMustBeFalse error for index 1
        vm.expectRevert(abi.encodeWithSelector(TrailsRouter.AllowFailureMustBeFalse.selector, 1));
        router.pullAmountAndExecute(address(erc20), 10 ether, callData);

        vm.stopPrank();
    }

    /**
     * @notice Test that pullAmountAndExecute reverts when allowFailure is true in the last of multiple calls
     * @dev Verifies that validation catches allowFailure=true at index 2
     */
    function test_RevertWhen_allowFailure_true_lastOfMultipleCalls() public {
        erc20.mint(user, 100 ether);
        vm.startPrank(user);
        erc20.approve(address(router), 100 ether);

        // Create multiple calls where the last one has allowFailure=true
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](3);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });
        calls[1] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: false, value: 0, callData: abi.encodeWithSignature("getSender()")
        });
        calls[2] = IMulticall3.Call3Value({
            target: address(getter),
            allowFailure: true, // This should cause revert
            value: 0,
            callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        // Should revert with AllowFailureMustBeFalse error for index 2
        vm.expectRevert(abi.encodeWithSelector(TrailsRouter.AllowFailureMustBeFalse.selector, 2));
        router.pullAmountAndExecute(address(erc20), 10 ether, callData);

        vm.stopPrank();
    }

    /**
     * @notice Test that pullAmountAndExecute reverts when all calls have allowFailure=true
     * @dev Verifies that validation catches the first allowFailure=true at index 0
     */
    function test_RevertWhen_allowFailure_true_allCalls() public {
        erc20.mint(user, 100 ether);
        vm.startPrank(user);
        erc20.approve(address(router), 100 ether);

        // Create multiple calls where all have allowFailure=true
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](3);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter),
            allowFailure: true, // This should cause revert
            value: 0,
            callData: abi.encodeWithSignature("getSender()")
        });
        calls[1] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: true, value: 0, callData: abi.encodeWithSignature("getSender()")
        });
        calls[2] = IMulticall3.Call3Value({
            target: address(getter), allowFailure: true, value: 0, callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        // Should revert with AllowFailureMustBeFalse error for index 0 (first occurrence)
        vm.expectRevert(abi.encodeWithSelector(TrailsRouter.AllowFailureMustBeFalse.selector, 0));
        router.pullAmountAndExecute(address(erc20), 10 ether, callData);

        vm.stopPrank();
    }

    /**
     * @notice Test that pullAndExecute also validates allowFailure flag
     * @dev Ensures the validation applies to pullAndExecute as well
     */
    function test_RevertWhen_pullAndExecute_allowFailure_true() public {
        erc20.mint(user, 100 ether);
        vm.startPrank(user);
        erc20.approve(address(router), 100 ether);

        // Create a call with allowFailure=true
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter),
            allowFailure: true, // This should cause revert
            value: 0,
            callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        // Should revert with AllowFailureMustBeFalse error for index 0
        vm.expectRevert(abi.encodeWithSelector(TrailsRouter.AllowFailureMustBeFalse.selector, 0));
        router.pullAndExecute(address(erc20), callData);

        vm.stopPrank();
    }

    /**
     * @notice Test that execute with ETH validates allowFailure flag
     * @dev Ensures the validation applies to all execution paths
     */
    function test_RevertWhen_execute_withETH_allowFailure_true() public {
        // Create a call with allowFailure=true
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(getter),
            allowFailure: true, // This should cause revert
            value: 0,
            callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSignature("aggregate3Value((address,bool,uint256,bytes)[])", calls);

        // Should revert with AllowFailureMustBeFalse error for index 0
        vm.expectRevert(abi.encodeWithSelector(TrailsRouter.AllowFailureMustBeFalse.selector, 0));
        router.pullAmountAndExecute{value: 1 ether}(address(0), 1 ether, callData);
    }
}
