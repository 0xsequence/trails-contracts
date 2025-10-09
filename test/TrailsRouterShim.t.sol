// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TrailsRouterShim} from "src/TrailsRouterShim.sol";
import {TrailsSentinelLib} from "src/libraries/TrailsSentinelLib.sol";

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
        vm.expectRevert(TrailsRouterShim.NotDelegateCall.selector);
        shimImpl.handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);
    }

    function test_delegatecall_forwards_and_sets_sentinel_and_bubbles_return() public {
        // Arrange: opHash and value
        bytes32 opHash = keccak256("test-op");
        uint256 callValue = 1 ether;
        vm.deal(holder, callValue);

        // Expect router event when forwarded
        bytes memory routerCalldata = abi.encodeWithSignature("doNothing(uint256)", uint256(123));
        bytes memory forwardData = abi.encode(routerCalldata, callValue);

        vm.expectEmit(true, true, true, true);
        emit MockRouter.Forwarded(holder, callValue, routerCalldata);

        // Act: delegate entrypoint
        IMockDelegatedExtension(holder).handleSequenceDelegateCall(opHash, 0, 0, 0, 0, forwardData);

        // Assert: success sentinel written at holder storage
        bytes32 slot = TrailsSentinelLib.successSlot(opHash);
        bytes32 stored = vm.load(holder, slot);
        assertEq(stored, TrailsSentinelLib.SUCCESS_VALUE);
    }

    function test_delegatecall_router_revert_bubbles_as_RouterCallFailed() public {
        // Swap router code at the existing router address with a reverting one
        RevertingRouter reverting = new RevertingRouter();
        vm.etch(address(router), address(reverting).code);

        // Prepare data
        bytes memory routerCalldata = abi.encodeWithSignature("willRevert()", "x");
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
}
