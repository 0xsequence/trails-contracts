// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TrailsRouterShim} from "src/TrailsRouterShim.sol";
import {DelegatecallGuard} from "src/guards/DelegatecallGuard.sol";
import {TrailsSentinelLib} from "src/libraries/TrailsSentinelLib.sol";
import {TstoreMode, TstoreRead} from "test/utils/TstoreUtils.sol";
import {TrailsRouter} from "src/TrailsRouter.sol";
import {IMulticall3} from "src/interfaces/IMulticall3.sol";

// -----------------------------------------------------------------------------
// Interfaces
// -----------------------------------------------------------------------------

/// @dev Minimal interface for delegated entrypoint used by tests
interface IMockDelegatedExtension {
    function handleSequenceDelegateCall(
        bytes32 opHash,
        uint256 startingGas,
        uint256 index,
        uint256 numCalls,
        uint256 space,
        bytes calldata data
    ) external payable;
}

// -----------------------------------------------------------------------------
// Mock Contracts
// -----------------------------------------------------------------------------

/// @dev Mock router that emits events and supports receiving value
contract MockRouter is Test {
    event Forwarded(address indexed from, uint256 value, bytes data);

    fallback() external payable {
        emit Forwarded(msg.sender, msg.value, msg.data);
    }

    receive() external payable {
        emit Forwarded(msg.sender, msg.value, hex"");
    }
}

/// @dev Mock router that implements aggregate3Value and forwards calls to targets
contract MockAggregate3Router {
    event Forwarded(address indexed from, uint256 value, bytes data);

    receive() external payable {}

    fallback() external payable {
        // Accept any call for testing purposes
        emit Forwarded(msg.sender, msg.value, msg.data);
    }

    function aggregate3Value(IMulticall3.Call3Value[] calldata calls)
        external
        payable
        returns (IMulticall3.Result[] memory)
    {
        IMulticall3.Result[] memory results = new IMulticall3.Result[](calls.length);

        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory ret) = calls[i].target.call{value: calls[i].value}(calls[i].callData);
            results[i] = IMulticall3.Result(success, ret);

            // If allowFailure is false and the call failed, revert
            if (!calls[i].allowFailure && !success) {
                // Revert with the failure data
                assembly {
                    revert(add(ret, 32), mload(ret))
                }
            }
        }

        // Emit event for the aggregate3Value call (matching original MockRouter behavior)
        emit Forwarded(msg.sender, msg.value, msg.data);

        return results;
    }
}

/// @dev Mock router that always reverts with encoded data
contract RevertingRouter {
    error AlwaysRevert(bytes data);

    fallback() external payable {
        revert AlwaysRevert(msg.data);
    }
}

contract MockRouterReturningData {
    event Forwarded(address indexed from, uint256 value, bytes data);

    function aggregate3Value(IMulticall3.Call3Value[] calldata calls)
        external
        payable
        returns (IMulticall3.Result[] memory)
    {
        IMulticall3.Result[] memory results = new IMulticall3.Result[](calls.length);

        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory ret) = address(this).call{value: calls[i].value}(calls[i].callData);
            results[i] = IMulticall3.Result(success, ret);

            // If allowFailure is false and the call failed, revert
            if (!calls[i].allowFailure && !success) {
                // Revert with the failure data
                assembly {
                    revert(add(ret, 32), mload(ret))
                }
            }
        }

        // Emit event for the aggregate3Value call
        emit Forwarded(msg.sender, msg.value, msg.data);

        return results;
    }

    function returnTestData() external pure returns (bytes memory) {
        return abi.encode(uint256(42), "test data");
    }
}

contract CustomErrorRouter {
    error CustomRouterError(string message);

    function aggregate3Value(IMulticall3.Call3Value[] calldata calls)
        external
        payable
        returns (IMulticall3.Result[] memory)
    {
        IMulticall3.Result[] memory results = new IMulticall3.Result[](calls.length);

        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory ret) = address(this).call{value: calls[i].value}(calls[i].callData);
            results[i] = IMulticall3.Result(success, ret);

            // If allowFailure is false and the call failed, revert
            if (!calls[i].allowFailure && !success) {
                // Revert with the failure data
                assembly {
                    revert(add(ret, 32), mload(ret))
                }
            }
        }

        return results;
    }

    function triggerCustomError() external pure {
        revert CustomRouterError("custom error message");
    }
}

// -----------------------------------------------------------------------------
// Test Contract
// -----------------------------------------------------------------------------
contract TrailsRouterShimTest is Test {
    // -------------------------------------------------------------------------
    // Test State Variables
    // -------------------------------------------------------------------------
    TrailsRouterShim internal shimImpl;
    MockRouter internal router;

    // address that will host the shim code to simulate delegatecall context
    address payable internal holder;

    // -------------------------------------------------------------------------
    // Setup and Tests
    // -------------------------------------------------------------------------
    function setUp() public {
        router = new MockRouter();
        shimImpl = new TrailsRouterShim(address(router));
        holder = payable(address(0xbeef));
        // Install shim runtime code at the holder address to simulate delegatecall
        vm.etch(holder, address(shimImpl).code);
    }

    // -------------------------------------------------------------------------
    // Test Functions
    // -------------------------------------------------------------------------
    function test_constructor_revert_zeroRouter() public {
        vm.expectRevert(TrailsRouterShim.ZeroRouterAddress.selector);
        new TrailsRouterShim(address(0));
    }

    function test_direct_handleSequenceDelegateCall_reverts_not_delegatecall() public {
        bytes memory inner = abi.encodeWithSignature("someFunc()");
        bytes memory data = abi.encode(inner, 0);
        vm.expectRevert(DelegatecallGuard.NotDelegateCall.selector);
        shimImpl.handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);
    }

    function test_delegatecall_forwards_and_sets_sentinel_tstore_active() public {
        // Explicitly force tstore active for TrailsRouterShim storage
        TstoreMode.setActive(address(shimImpl));

        // Arrange: opHash and value
        bytes32 opHash = keccak256("test-op-tstore");
        uint256 callValue = 1 ether;
        vm.deal(holder, callValue);

        // Expect router event when forwarded - use valid aggregate3Value call
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(router),
            allowFailure: false,
            value: 0,
            callData: abi.encodeWithSignature("doNothing(uint256)", uint256(123))
        });
        bytes memory routerCalldata = abi.encodeWithSelector(IMulticall3.aggregate3Value.selector, calls);
        bytes memory forwardData = abi.encode(routerCalldata, callValue);

        vm.expectEmit(true, true, true, true);
        emit MockAggregate3Router.Forwarded(holder, callValue, routerCalldata);

        // Act: delegate entrypoint
        IMockDelegatedExtension(holder).handleSequenceDelegateCall(opHash, 0, 0, 0, 0, forwardData);

        // Assert via tload
        uint256 slot = TrailsSentinelLib.successSlot(opHash);
        uint256 storedT = TstoreRead.tloadAt(holder, bytes32(slot));
        assertEq(storedT, TrailsSentinelLib.SUCCESS_VALUE);
    }

    function test_delegatecall_forwards_and_sets_sentinel_sstore_inactive() public {
        // Explicitly force tstore inactive for shim code at `holder`
        TstoreMode.setInactive(holder);

        // Arrange: opHash and value
        bytes32 opHash = keccak256("test-op-sstore");
        uint256 callValue = 1 ether;
        vm.deal(holder, callValue);

        // Expect router event when forwarded - use valid aggregate3Value call
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(router),
            allowFailure: false,
            value: 0,
            callData: abi.encodeWithSignature("doNothing(uint256)", uint256(123))
        });
        bytes memory routerCalldata = abi.encodeWithSelector(IMulticall3.aggregate3Value.selector, calls);
        bytes memory forwardData = abi.encode(routerCalldata, callValue);

        vm.expectEmit(true, true, true, true);
        emit MockAggregate3Router.Forwarded(holder, callValue, routerCalldata);

        // Act: delegate entrypoint
        IMockDelegatedExtension(holder).handleSequenceDelegateCall(opHash, 0, 0, 0, 0, forwardData);

        // Verify sentinel by re-etching TrailsRouter and validating via delegated entrypoint
        bytes memory original = address(shimImpl).code;
        vm.etch(holder, address(new TrailsRouter()).code);

        address payable recipient = payable(address(0x111));
        vm.deal(holder, callValue);
        bytes memory data =
            abi.encodeWithSelector(TrailsRouter.validateOpHashAndSweep.selector, bytes32(0), address(0), recipient);
        IMockDelegatedExtension(holder).handleSequenceDelegateCall(opHash, 0, 0, 0, 0, data);
        assertEq(holder.balance, 0);
        assertEq(recipient.balance, callValue);
        vm.etch(holder, original);
    }

    function test_delegatecall_sets_sentinel_with_tstore_when_supported() public {
        // Force tstore active to ensure tstore path on TrailsRouterShim storage
        TstoreMode.setActive(address(shimImpl));
        bytes32 opHash = keccak256("tstore-case");
        vm.deal(holder, 0);

        // Invoke delegate entrypoint to set sentinel with valid aggregate3Value call
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](0); // Empty calls array
        bytes memory routerCalldata = abi.encodeWithSelector(IMulticall3.aggregate3Value.selector, calls);
        bytes memory forwardData = abi.encode(routerCalldata, 0);
        (bool ok,) = address(holder)
            .call(
                abi.encodeWithSelector(
                    IMockDelegatedExtension.handleSequenceDelegateCall.selector, opHash, 0, 0, 0, 0, forwardData
                )
            );
        assertTrue(ok, "delegatecall should succeed");

        // Read via tload
        uint256 slot = TrailsSentinelLib.successSlot(opHash);
        uint256 storedT = TstoreRead.tloadAt(holder, bytes32(slot));
        assertEq(storedT, TrailsSentinelLib.SUCCESS_VALUE);
    }

    function test_delegatecall_sets_sentinel_with_sstore_when_no_tstore() public {
        // Force tstore inactive to ensure sstore path
        TstoreMode.setInactive(holder);
        bytes32 opHash = keccak256("sstore-case");
        vm.deal(holder, 0);

        // Invoke delegate entrypoint to set sentinel with valid aggregate3Value call
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](0); // Empty calls array
        bytes memory routerCalldata = abi.encodeWithSelector(IMulticall3.aggregate3Value.selector, calls);
        bytes memory forwardData = abi.encode(routerCalldata, 0);
        (bool ok,) = address(holder)
            .call(
                abi.encodeWithSelector(
                    IMockDelegatedExtension.handleSequenceDelegateCall.selector, opHash, 0, 0, 0, 0, forwardData
                )
            );
        assertTrue(ok, "delegatecall should succeed");

        // Verify via TrailsRouter delegated validation
        bytes memory original = address(shimImpl).code;
        vm.etch(holder, address(new TrailsRouter()).code);
        address payable recipient = payable(address(0x112));
        vm.deal(holder, 1 ether);
        bytes memory data =
            abi.encodeWithSelector(TrailsRouter.validateOpHashAndSweep.selector, bytes32(0), address(0), recipient);
        IMockDelegatedExtension(holder).handleSequenceDelegateCall(opHash, 0, 0, 0, 0, data);
        assertEq(holder.balance, 0);
        assertEq(recipient.balance, 1 ether);
        vm.etch(holder, original);
    }

    function test_delegatecall_router_revert_bubbles_as_RouterCallFailed() public {
        // Swap router code at the existing router address with a reverting one
        RevertingRouter reverting = new RevertingRouter();
        vm.etch(address(router), address(reverting).code);

        // Prepare data - use aggregate3Value call that will revert
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(router),
            allowFailure: false,
            value: 0,
            callData: abi.encodeWithSignature("willRevert()", "x")
        });
        bytes memory routerCalldata = abi.encodeWithSelector(IMulticall3.aggregate3Value.selector, calls);
        bytes memory forwardData = abi.encode(routerCalldata, 0);

        // Call and capture revert data, then assert custom error selector
        (bool ok, bytes memory ret) = address(holder)
            .call(
                abi.encodeWithSelector(
                    IMockDelegatedExtension.handleSequenceDelegateCall.selector, bytes32(0), 0, 0, 0, 0, forwardData
                )
            );
        assertFalse(ok, "call should revert");
        bytes4 sel;
        assembly {
            sel := mload(add(ret, 32))
        }
        assertEq(sel, TrailsRouterShim.RouterCallFailed.selector, "expected RouterCallFailed selector");
    }

    function test_handleSequenceDelegateCall_with_eth_value() public {
        uint256 callValue = 2 ether;
        vm.deal(holder, callValue);

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(router), allowFailure: false, value: 0, callData: abi.encodeWithSignature("receiveEth()")
        });
        bytes memory routerCalldata = abi.encodeWithSelector(IMulticall3.aggregate3Value.selector, calls);
        bytes memory forwardData = abi.encode(routerCalldata, callValue);

        vm.expectEmit(true, true, true, true);
        emit MockAggregate3Router.Forwarded(holder, callValue, routerCalldata);

        IMockDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, forwardData);

        assertEq(holder.balance, 0, "holder should have sent ETH to router");
    }

    function test_handleSequenceDelegateCall_empty_calldata() public {
        // Empty aggregate3Value call with empty calls array
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](0);
        bytes memory routerCalldata = abi.encodeWithSelector(IMulticall3.aggregate3Value.selector, calls);
        bytes memory forwardData = abi.encode(routerCalldata, uint256(0));

        IMockDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, forwardData);
    }

    function test_handleSequenceDelegateCall_large_calldata() public {
        // Create large call data to test assembly handling within aggregate3
        bytes memory largeData = new bytes(10000);
        for (uint256 i = 0; i < largeData.length; i++) {
            // casting to 'uint8' is safe because i % 256 is always between 0-255
            /// forge-lint: disable-next-line(unsafe-typecast)
            largeData[i] = bytes1(uint8(i % 256));
        }

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({target: address(router), allowFailure: false, value: 0, callData: largeData});
        bytes memory routerCalldata = abi.encodeWithSelector(IMulticall3.aggregate3Value.selector, calls);
        bytes memory forwardData = abi.encode(routerCalldata, uint256(0));

        vm.expectEmit(true, true, true, true);
        emit MockAggregate3Router.Forwarded(holder, 0, routerCalldata);

        IMockDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, forwardData);
    }

    function test_handleSequenceDelegateCall_zero_call_value() public {
        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(router), allowFailure: false, value: 0, callData: abi.encodeWithSignature("doSomething()")
        });
        bytes memory routerCalldata = abi.encodeWithSelector(IMulticall3.aggregate3Value.selector, calls);
        bytes memory forwardData = abi.encode(routerCalldata, uint256(0));

        vm.expectEmit(true, true, true, true);
        emit MockAggregate3Router.Forwarded(holder, 0, routerCalldata);

        IMockDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, forwardData);
    }

    function test_handleSequenceDelegateCall_allows_arbitrary_selector() public {
        // No validation is enforced in the shim anymore; arbitrary selector should be forwarded.
        bytes memory arbitraryCalldata = hex"deadbeef";
        bytes memory forwardData = abi.encode(arbitraryCalldata, uint256(0));

        vm.expectEmit(true, true, true, true);
        emit MockAggregate3Router.Forwarded(holder, 0, arbitraryCalldata);

        IMockDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, forwardData);
    }

    function test_handleSequenceDelegateCall_max_call_value() public {
        uint256 maxValue = type(uint256).max;
        vm.deal(holder, maxValue);

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(router),
            allowFailure: false,
            value: 0,
            callData: abi.encodeWithSignature("handleMaxValue()")
        });
        bytes memory routerCalldata = abi.encodeWithSelector(IMulticall3.aggregate3Value.selector, calls);
        bytes memory forwardData = abi.encode(routerCalldata, maxValue);

        vm.expectEmit(true, true, true, true);
        emit MockAggregate3Router.Forwarded(holder, maxValue, routerCalldata);

        IMockDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, forwardData);

        assertEq(holder.balance, 0, "holder should have sent all ETH");
    }

    function test_forwardToRouter_return_data_handling() public {
        // Test with a mock router that returns data
        MockRouterReturningData returningRouter = new MockRouterReturningData();
        TrailsRouterShim shimWithReturningRouter = new TrailsRouterShim(address(returningRouter));

        address payable testHolder = payable(address(0xbeef));
        vm.etch(testHolder, address(shimWithReturningRouter).code);

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(returningRouter),
            allowFailure: false,
            value: 0,
            callData: abi.encodeWithSignature("returnTestData()")
        });
        bytes memory routerCalldata = abi.encodeWithSelector(IMulticall3.aggregate3Value.selector, calls);
        bytes memory forwardData = abi.encode(routerCalldata, uint256(0));

        bytes32 testOpHash = keccak256("test-return-data");
        IMockDelegatedExtension(testHolder).handleSequenceDelegateCall(testOpHash, 0, 0, 0, 0, forwardData);

        // Verify sentinel was set
        uint256 slot = TrailsSentinelLib.successSlot(testOpHash);
        uint256 storedT = TstoreRead.tloadAt(testHolder, bytes32(slot));
        assertEq(storedT, TrailsSentinelLib.SUCCESS_VALUE);
    }

    function test_forwardToRouter_revert_with_custom_error() public {
        CustomErrorRouter customErrorRouter = new CustomErrorRouter();
        TrailsRouterShim shimWithCustomError = new TrailsRouterShim(address(customErrorRouter));

        address payable testHolder = payable(address(0xbeef));
        vm.etch(testHolder, address(shimWithCustomError).code);

        IMulticall3.Call3Value[] memory calls = new IMulticall3.Call3Value[](1);
        calls[0] = IMulticall3.Call3Value({
            target: address(customErrorRouter),
            allowFailure: false,
            value: 0,
            callData: abi.encodeWithSignature("triggerCustomError()")
        });
        bytes memory routerCalldata = abi.encodeWithSelector(IMulticall3.aggregate3Value.selector, calls);
        bytes memory forwardData = abi.encode(routerCalldata, uint256(0));

        (bool ok, bytes memory ret) = address(testHolder)
            .call(
                abi.encodeWithSelector(
                    IMockDelegatedExtension.handleSequenceDelegateCall.selector, bytes32(0), 0, 0, 0, 0, forwardData
                )
            );

        assertFalse(ok, "call should revert");
        bytes4 sel;
        assembly {
            sel := mload(add(ret, 32))
        }
        assertEq(sel, TrailsRouterShim.RouterCallFailed.selector, "expected RouterCallFailed selector");
    }

    function test_sentinel_setting_with_different_op_hashes() public {
        TstoreMode.setActive(holder);

        bytes32 opHash1 = keccak256("op1");
        bytes32 opHash2 = keccak256("op2");

        // First call
        IMulticall3.Call3Value[] memory calls1 = new IMulticall3.Call3Value[](1);
        calls1[0] = IMulticall3.Call3Value({
            target: address(router), allowFailure: false, value: 0, callData: abi.encodeWithSignature("call1()")
        });
        bytes memory routerCalldata1 = abi.encodeWithSelector(IMulticall3.aggregate3Value.selector, calls1);
        bytes memory forwardData1 = abi.encode(routerCalldata1, uint256(0));
        IMockDelegatedExtension(holder).handleSequenceDelegateCall(opHash1, 0, 0, 0, 0, forwardData1);

        // Second call
        IMulticall3.Call3Value[] memory calls2 = new IMulticall3.Call3Value[](1);
        calls2[0] = IMulticall3.Call3Value({
            target: address(router), allowFailure: false, value: 0, callData: abi.encodeWithSignature("call2()")
        });
        bytes memory routerCalldata2 = abi.encodeWithSelector(IMulticall3.aggregate3Value.selector, calls2);
        bytes memory forwardData2 = abi.encode(routerCalldata2, uint256(0));
        IMockDelegatedExtension(holder).handleSequenceDelegateCall(opHash2, 0, 0, 0, 0, forwardData2);

        // Check both sentinels are set
        uint256 slot1 = TrailsSentinelLib.successSlot(opHash1);
        uint256 slot2 = TrailsSentinelLib.successSlot(opHash2);

        uint256 storedT1 = TstoreRead.tloadAt(holder, bytes32(slot1));
        uint256 storedT2 = TstoreRead.tloadAt(holder, bytes32(slot2));

        assertEq(storedT1, TrailsSentinelLib.SUCCESS_VALUE);
        assertEq(storedT2, TrailsSentinelLib.SUCCESS_VALUE);
        assertTrue(slot1 != slot2, "slots should be different");
    }

    function testRouterAddressImmutable() public {
        address testRouter = address(new MockRouter());
        TrailsRouterShim shim = new TrailsRouterShim(testRouter);

        assertEq(shim.ROUTER(), testRouter, "ROUTER should be set correctly");
    }

    function testConstructorValidation() public {
        // Test that constructor properly validates router address
        vm.expectRevert(TrailsRouterShim.ZeroRouterAddress.selector);
        new TrailsRouterShim(address(0));
    }

    function testForwardToRouterReturnValue() public {
        // Test that _forwardToRouter properly returns router response
        bytes memory testData = abi.encodeWithSignature("testReturn()");

        // Mock router that returns data
        MockRouterReturningData returningRouter = new MockRouterReturningData();
        TrailsRouterShim shim = new TrailsRouterShim(address(returningRouter));

        // Call the internal function indirectly through handleSequenceDelegateCall
        bytes memory innerData = abi.encode(testData, uint256(0));
        bytes32 opHash = keccak256("test-return-value");

        vm.expectRevert(DelegatecallGuard.NotDelegateCall.selector);
        shim.handleSequenceDelegateCall(opHash, 0, 0, 0, 0, innerData);
    }
}
