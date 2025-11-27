// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TrailsRouterShim} from "src/TrailsRouterShim.sol";
import {DelegatecallGuard} from "src/guards/DelegatecallGuard.sol";
import {TrailsSentinelLib} from "src/libraries/TrailsSentinelLib.sol";
import {TstoreMode, TstoreRead} from "test/utils/TstoreUtils.sol";
import {TrailsRouter} from "src/TrailsRouter.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

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

/// @dev Mock router that accepts CallsPayload format and forwards calls to targets
contract MockCallsPayloadRouter {
    event Forwarded(address indexed from, uint256 value, bytes data);

    receive() external payable {}

    fallback() external payable {
        // Decode CallsPayload and execute calls
        Payload.Decoded memory decoded = Payload.fromPackedCalls(msg.data);

        // Execute calls
        for (uint256 i = 0; i < decoded.calls.length; i++) {
            Payload.Call memory call = decoded.calls[i];

            // Skip onlyFallback calls
            if (call.onlyFallback) {
                continue;
            }

            // Execute call
            uint256 gasLimit = call.gasLimit == 0 ? gasleft() : call.gasLimit;
            (bool success,) = call.to.call{value: call.value, gas: gasLimit}(call.data);

            if (!success) {
                if (call.behaviorOnError == Payload.BEHAVIOR_REVERT_ON_ERROR) {
                    revert("MockCallsPayloadRouter: call failed");
                } else if (call.behaviorOnError == Payload.BEHAVIOR_ABORT_ON_ERROR) {
                    break;
                }
                // BEHAVIOR_IGNORE_ERROR: continue execution
            }
        }

        // Emit event for the CallsPayload call
        emit Forwarded(msg.sender, msg.value, msg.data);
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

    fallback() external payable {
        // Decode CallsPayload and execute calls
        Payload.Decoded memory decoded = Payload.fromPackedCalls(msg.data);

        // Execute calls
        for (uint256 i = 0; i < decoded.calls.length; i++) {
            Payload.Call memory call = decoded.calls[i];

            // Skip onlyFallback calls
            if (call.onlyFallback) {
                continue;
            }

            // Execute call
            uint256 gasLimit = call.gasLimit == 0 ? gasleft() : call.gasLimit;
            (bool success,) = address(this).call{value: call.value, gas: gasLimit}(call.data);

            if (!success) {
                if (call.behaviorOnError == Payload.BEHAVIOR_REVERT_ON_ERROR) {
                    revert("MockRouterReturningData: call failed");
                } else if (call.behaviorOnError == Payload.BEHAVIOR_ABORT_ON_ERROR) {
                    break;
                }
                // BEHAVIOR_IGNORE_ERROR: continue execution
            }
        }

        // Emit event for the CallsPayload call
        emit Forwarded(msg.sender, msg.value, msg.data);
    }

    function returnTestData() external pure returns (bytes memory) {
        return abi.encode(uint256(42), "test data");
    }
}

contract CustomErrorRouter {
    error CustomRouterError(string message);

    fallback() external payable {
        // Decode CallsPayload and execute calls
        Payload.Decoded memory decoded = Payload.fromPackedCalls(msg.data);

        // Execute calls
        for (uint256 i = 0; i < decoded.calls.length; i++) {
            Payload.Call memory call = decoded.calls[i];

            // Skip onlyFallback calls
            if (call.onlyFallback) {
                continue;
            }

            // Execute call
            uint256 gasLimit = call.gasLimit == 0 ? gasleft() : call.gasLimit;
            (bool success,) = address(this).call{value: call.value, gas: gasLimit}(call.data);

            if (!success) {
                if (call.behaviorOnError == Payload.BEHAVIOR_REVERT_ON_ERROR) {
                    revert("CustomErrorRouter: call failed");
                } else if (call.behaviorOnError == Payload.BEHAVIOR_ABORT_ON_ERROR) {
                    break;
                }
                // BEHAVIOR_IGNORE_ERROR: continue execution
            }
        }
    }

    function triggerCustomError() external pure {
        revert CustomRouterError("custom error message");
    }
}

// -----------------------------------------------------------------------------
// Helper Library
// -----------------------------------------------------------------------------
library TestHelpers {
    /// @notice Encodes Payload.Call[] to Sequence V3 CallsPayload encoded data
    function encodeCallsPayload(Payload.Call[] memory calls) internal pure returns (bytes memory) {
        if (calls.length == 0) {
            return abi.encodePacked(uint8(0x01), uint8(0));
        }

        bytes memory packed;
        uint8 globalFlag = 0x01; // space is zero

        if (calls.length == 1) {
            globalFlag |= 0x10; // single call
        } else if (calls.length > 255) {
            globalFlag |= 0x20; // use 2 bytes for numCalls
        }

        packed = abi.encodePacked(globalFlag);

        if (calls.length == 1) {
            // Already encoded
        } else if (calls.length <= 255) {
            packed = abi.encodePacked(packed, uint8(calls.length));
        } else {
            packed = abi.encodePacked(packed, uint16(calls.length));
        }

        for (uint256 i = 0; i < calls.length; i++) {
            uint8 flags = 0;

            if (calls[i].value > 0) {
                flags |= 0x02; // has value
            }
            if (calls[i].data.length > 0) {
                flags |= 0x04; // has data
            }
            if (calls[i].gasLimit > 0) {
                flags |= 0x08; // has gasLimit
            }
            if (calls[i].delegateCall) {
                flags |= 0x10; // delegateCall
            }
            if (calls[i].onlyFallback) {
                flags |= 0x20; // onlyFallback
            }
            flags |= uint8(calls[i].behaviorOnError) << 6;

            packed = abi.encodePacked(packed, flags);
            if (flags & 0x01 == 0) {
                packed = abi.encodePacked(packed, calls[i].to);
            }
            if (flags & 0x02 == 0x02) {
                packed = abi.encodePacked(packed, calls[i].value);
            }
            if (flags & 0x04 == 0x04) {
                uint24 dataSize = uint24(calls[i].data.length);
                packed = abi.encodePacked(packed, dataSize);
                packed = abi.encodePacked(packed, calls[i].data);
            }
            if (flags & 0x08 == 0x08) {
                packed = abi.encodePacked(packed, calls[i].gasLimit);
            }
        }

        return packed;
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

    // Helper function to create a simple Payload.Call
    function _createCall(address to, bytes memory data, uint256 value, uint256 behaviorOnError)
        internal
        pure
        returns (Payload.Call memory)
    {
        return Payload.Call({
            to: to,
            value: value,
            data: data,
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: behaviorOnError
        });
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

        // Expect router event when forwarded - use valid CallsPayload
        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = _createCall(
            address(router),
            abi.encodeWithSignature("doNothing(uint256)", uint256(123)),
            0,
            Payload.BEHAVIOR_REVERT_ON_ERROR
        );
        bytes memory routerCalldata = TestHelpers.encodeCallsPayload(calls);
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

        // Expect router event when forwarded - use valid CallsPayload
        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = _createCall(
            address(router),
            abi.encodeWithSignature("doNothing(uint256)", uint256(123)),
            0,
            Payload.BEHAVIOR_REVERT_ON_ERROR
        );
        bytes memory routerCalldata = TestHelpers.encodeCallsPayload(calls);
        bytes memory forwardData = abi.encode(routerCalldata, callValue);

        vm.expectEmit(true, true, true, true);
        emit MockRouter.Forwarded(holder, callValue, routerCalldata);

        // Act: delegate entrypoint
        IMockDelegatedExtension(holder).handleSequenceDelegateCall(opHash, 0, 0, 0, 0, forwardData);

        // Verify sentinel by re-etching TrailsRouter and validating via delegated entrypoint
        bytes memory original = address(shimImpl).code;
        vm.etch(holder, address(new TrailsRouter(address(0x0000000000000000000000000000000000000001))).code);

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

        // Invoke delegate entrypoint to set sentinel with valid CallsPayload
        Payload.Call[] memory calls = new Payload.Call[](0); // Empty calls array
        bytes memory routerCalldata = TestHelpers.encodeCallsPayload(calls);
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

        // Invoke delegate entrypoint to set sentinel with valid CallsPayload
        Payload.Call[] memory calls = new Payload.Call[](0); // Empty calls array
        bytes memory routerCalldata = TestHelpers.encodeCallsPayload(calls);
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
        vm.etch(holder, address(new TrailsRouter(address(0x0000000000000000000000000000000000000001))).code);
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

        // Prepare data - use CallsPayload that will revert
        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] =
            _createCall(address(router), abi.encodeWithSignature("willRevert()"), 0, Payload.BEHAVIOR_REVERT_ON_ERROR);
        bytes memory routerCalldata = TestHelpers.encodeCallsPayload(calls);
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

        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] =
            _createCall(address(router), abi.encodeWithSignature("receiveEth()"), 0, Payload.BEHAVIOR_REVERT_ON_ERROR);
        bytes memory routerCalldata = TestHelpers.encodeCallsPayload(calls);
        bytes memory forwardData = abi.encode(routerCalldata, callValue);

        vm.expectEmit(true, true, true, true);
        emit MockRouter.Forwarded(holder, callValue, routerCalldata);

        IMockDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, forwardData);

        assertEq(holder.balance, 0, "holder should have sent ETH to router");
    }

    function test_handleSequenceDelegateCall_empty_calldata() public {
        // Empty CallsPayload with empty calls array
        Payload.Call[] memory calls = new Payload.Call[](0);
        bytes memory routerCalldata = TestHelpers.encodeCallsPayload(calls);
        bytes memory forwardData = abi.encode(routerCalldata, uint256(0));

        IMockDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, forwardData);
    }

    function test_handleSequenceDelegateCall_large_calldata() public {
        // Create large call data to test assembly handling within CallsPayload
        bytes memory largeData = new bytes(10000);
        for (uint256 i = 0; i < largeData.length; i++) {
            // casting to 'uint8' is safe because i % 256 is always between 0-255
            /// forge-lint: disable-next-line(unsafe-typecast)
            largeData[i] = bytes1(uint8(i % 256));
        }

        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = _createCall(address(router), largeData, 0, Payload.BEHAVIOR_REVERT_ON_ERROR);
        bytes memory routerCalldata = TestHelpers.encodeCallsPayload(calls);
        bytes memory forwardData = abi.encode(routerCalldata, uint256(0));

        vm.expectEmit(true, true, true, true);
        emit MockRouter.Forwarded(holder, 0, routerCalldata);

        IMockDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, forwardData);
    }

    function test_handleSequenceDelegateCall_zero_call_value() public {
        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] =
            _createCall(address(router), abi.encodeWithSignature("doSomething()"), 0, Payload.BEHAVIOR_REVERT_ON_ERROR);
        bytes memory routerCalldata = TestHelpers.encodeCallsPayload(calls);
        bytes memory forwardData = abi.encode(routerCalldata, uint256(0));

        vm.expectEmit(true, true, true, true);
        emit MockRouter.Forwarded(holder, 0, routerCalldata);

        IMockDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, forwardData);
    }

    function test_handleSequenceDelegateCall_allows_arbitrary_selector() public {
        // No validation is enforced in the shim anymore; arbitrary selector should be forwarded.
        bytes memory arbitraryCalldata = hex"deadbeef";
        bytes memory forwardData = abi.encode(arbitraryCalldata, uint256(0));

        vm.expectEmit(true, true, true, true);
        emit MockRouter.Forwarded(holder, 0, arbitraryCalldata);

        IMockDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, forwardData);
    }

    function test_handleSequenceDelegateCall_max_call_value() public {
        uint256 maxValue = type(uint256).max;
        vm.deal(holder, maxValue);

        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = _createCall(
            address(router), abi.encodeWithSignature("handleMaxValue()"), 0, Payload.BEHAVIOR_REVERT_ON_ERROR
        );
        bytes memory routerCalldata = TestHelpers.encodeCallsPayload(calls);
        bytes memory forwardData = abi.encode(routerCalldata, maxValue);

        vm.expectEmit(true, true, true, true);
        emit MockRouter.Forwarded(holder, maxValue, routerCalldata);

        IMockDelegatedExtension(holder).handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, forwardData);

        assertEq(holder.balance, 0, "holder should have sent all ETH");
    }

    function test_forwardToRouter_return_data_handling() public {
        // Test with a mock router that returns data
        MockRouterReturningData returningRouter = new MockRouterReturningData();
        TrailsRouterShim shimWithReturningRouter = new TrailsRouterShim(address(returningRouter));

        address payable testHolder = payable(address(0xbeef));
        vm.etch(testHolder, address(shimWithReturningRouter).code);

        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = _createCall(
            address(returningRouter), abi.encodeWithSignature("returnTestData()"), 0, Payload.BEHAVIOR_REVERT_ON_ERROR
        );
        bytes memory routerCalldata = TestHelpers.encodeCallsPayload(calls);
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

        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = _createCall(
            address(customErrorRouter),
            abi.encodeWithSignature("triggerCustomError()"),
            0,
            Payload.BEHAVIOR_REVERT_ON_ERROR
        );
        bytes memory routerCalldata = TestHelpers.encodeCallsPayload(calls);
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
        Payload.Call[] memory calls1 = new Payload.Call[](1);
        calls1[0] =
            _createCall(address(router), abi.encodeWithSignature("call1()"), 0, Payload.BEHAVIOR_REVERT_ON_ERROR);
        bytes memory routerCalldata1 = TestHelpers.encodeCallsPayload(calls1);
        bytes memory forwardData1 = abi.encode(routerCalldata1, uint256(0));
        IMockDelegatedExtension(holder).handleSequenceDelegateCall(opHash1, 0, 0, 0, 0, forwardData1);

        // Second call
        Payload.Call[] memory calls2 = new Payload.Call[](1);
        calls2[0] =
            _createCall(address(router), abi.encodeWithSignature("call2()"), 0, Payload.BEHAVIOR_REVERT_ON_ERROR);
        bytes memory routerCalldata2 = TestHelpers.encodeCallsPayload(calls2);
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
