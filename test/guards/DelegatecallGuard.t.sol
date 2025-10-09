// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DelegatecallGuard} from "src/guards/DelegatecallGuard.sol";

// -----------------------------------------------------------------------------
// Mock Contracts
// -----------------------------------------------------------------------------

/// @dev Minimal contract using DelegatecallGuard
contract MockGuarded is DelegatecallGuard {
    event Ping(address sender);

    function ping() external onlyDelegatecall {
        emit Ping(msg.sender);
    }
}

/// @dev Host that can delegatecall into a target
contract MockHost {
    function callPing(address target) external returns (bool ok, bytes memory ret) {
        return target.delegatecall(abi.encodeWithSelector(MockGuarded.ping.selector));
    }
}

contract DelegatecallGuardTest is Test {
    // -------------------------------------------------------------------------
    // Test State Variables
    // -------------------------------------------------------------------------
    MockGuarded internal guarded;
    MockHost internal host;

    // -------------------------------------------------------------------------
    // Setup and Tests
    // -------------------------------------------------------------------------
    function setUp() public {
        guarded = new MockGuarded();
        host = new MockHost();
    }

    // -------------------------------------------------------------------------
    // Test Functions
    // -------------------------------------------------------------------------
    function test_direct_call_reverts_NotDelegateCall() public {
        vm.expectRevert(DelegatecallGuard.NotDelegateCall.selector);
        guarded.ping();
    }

    function test_delegatecall_context_succeeds() public {
        vm.expectEmit(true, false, false, true);
        emit MockGuarded.Ping(address(this));
        (bool ok,) = host.callPing(address(guarded));
        assertTrue(ok, "delegatecall-context ping should succeed");
    }
}
