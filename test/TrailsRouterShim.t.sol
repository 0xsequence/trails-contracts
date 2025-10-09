// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TrailsRouterShim} from "src/TrailsRouterShim.sol";
import {DelegatecallGuard} from "src/guards/DelegatecallGuard.sol";
import {TrailsSentinelLib} from "src/libraries/TrailsSentinelLib.sol";
import {TstoreMode, TstoreRead} from "test/utils/TstoreUtils.sol";
import {TrailsRouter} from "src/TrailsRouter.sol";

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

/// @dev Mock router that always reverts with encoded data
contract RevertingRouter {
    error AlwaysRevert(bytes data);

    fallback() external payable {
        revert AlwaysRevert(msg.data);
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

        // Expect router event when forwarded
        bytes memory routerCalldata = abi.encodeWithSignature("doNothing(uint256)", uint256(123));
        bytes memory forwardData = abi.encode(routerCalldata, callValue);

        vm.expectEmit(true, true, true, true);
        emit MockRouter.Forwarded(holder, callValue, routerCalldata);

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

        // Expect router event when forwarded
        bytes memory routerCalldata = abi.encodeWithSignature("doNothing(uint256)", uint256(123));
        bytes memory forwardData = abi.encode(routerCalldata, callValue);

        vm.expectEmit(true, true, true, true);
        emit MockRouter.Forwarded(holder, callValue, routerCalldata);

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

        // Invoke delegate entrypoint to set sentinel
        bytes memory routerCalldata = hex"";
        bytes memory forwardData = abi.encode(routerCalldata, 0);
        (bool ok,) = address(holder).call(
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

        // Invoke delegate entrypoint to set sentinel
        bytes memory routerCalldata = hex"";
        bytes memory forwardData = abi.encode(routerCalldata, 0);
        (bool ok,) = address(holder).call(
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

        // Prepare data
        bytes memory routerCalldata = abi.encodeWithSignature("willRevert()", "x");
        bytes memory forwardData = abi.encode(routerCalldata, 0);

        // Call and capture revert data, then assert custom error selector
        (bool ok, bytes memory ret) = address(holder).call(
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
}
