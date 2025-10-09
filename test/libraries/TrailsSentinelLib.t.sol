// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TrailsSentinelLib} from "src/libraries/TrailsSentinelLib.sol";

// -----------------------------------------------------------------------------
// Test Contract
// -----------------------------------------------------------------------------
contract TrailsSentinelLibTest is Test {
    // -------------------------------------------------------------------------
    // Tests
    // -------------------------------------------------------------------------

    function test_SentinelNamespace_Constant() public pure {
        bytes32 expected = keccak256("org.sequence.trails.router.sentinel");
        assertEq(TrailsSentinelLib.SENTINEL_NAMESPACE, expected);
    }

    function test_SuccessValue_Constant() public pure {
        assertEq(TrailsSentinelLib.SUCCESS_VALUE, uint256(1));
    }

    function test_SuccessSlot_DifferentOpHashes() public pure {
        bytes32 opHash1 = keccak256("operation1");
        bytes32 opHash2 = keccak256("operation2");

        uint256 slot1 = TrailsSentinelLib.successSlot(opHash1);
        uint256 slot2 = TrailsSentinelLib.successSlot(opHash2);

        assertTrue(slot1 != slot2, "Different opHashes should produce different slots");
    }

    function test_SuccessSlot_Deterministic() public pure {
        bytes32 opHash = keccak256("test-operation");
        uint256 slot1 = TrailsSentinelLib.successSlot(opHash);
        uint256 slot2 = TrailsSentinelLib.successSlot(opHash);

        assertEq(slot1, slot2, "Same opHash should always produce same slot");
    }

    function test_SuccessSlot_Computation() public pure {
        bytes32 opHash = keccak256("test-op");
        bytes32 namespace = TrailsSentinelLib.SENTINEL_NAMESPACE;

        // Manually compute expected slot
        bytes32 expectedKey;
        assembly {
            mstore(0x00, namespace)
            mstore(0x20, opHash)
            expectedKey := keccak256(0x00, 0x40)
        }
        uint256 expectedSlot = uint256(expectedKey);

        uint256 actualSlot = TrailsSentinelLib.successSlot(opHash);
        assertEq(actualSlot, expectedSlot, "Slot computation should match manual calculation");
    }

    function test_SuccessSlot_ZeroOpHash() public pure {
        bytes32 opHash = bytes32(0);
        uint256 slot = TrailsSentinelLib.successSlot(opHash);

        bytes32 namespace = TrailsSentinelLib.SENTINEL_NAMESPACE;
        bytes32 expectedKey;
        assembly {
            mstore(0x00, namespace)
            mstore(0x20, opHash)
            expectedKey := keccak256(0x00, 0x40)
        }
        uint256 expectedSlot = uint256(expectedKey);

        assertEq(slot, expectedSlot, "Zero opHash should produce valid slot");
    }

    function test_SuccessSlot_MaxOpHash() public pure {
        bytes32 opHash = bytes32(type(uint256).max);
        uint256 slot = TrailsSentinelLib.successSlot(opHash);

        bytes32 namespace = TrailsSentinelLib.SENTINEL_NAMESPACE;
        bytes32 expectedKey;
        assembly {
            mstore(0x00, namespace)
            mstore(0x20, opHash)
            expectedKey := keccak256(0x00, 0x40)
        }
        uint256 expectedSlot = uint256(expectedKey);

        assertEq(slot, expectedSlot, "Max opHash should produce valid slot");
    }

    function test_SuccessSlot_VariousOpHashes() public pure {
        bytes32[] memory opHashes = new bytes32[](5);
        opHashes[0] = keccak256("op1");
        opHashes[1] = keccak256("op2");
        opHashes[2] = keccak256(abi.encodePacked("complex", uint256(123), address(0x123)));
        opHashes[3] = keccak256(abi.encodePacked(uint256(1234567890), address(0x123)));
        opHashes[4] = bytes32(uint256(0x123456789abcdef));

        uint256[] memory slots = new uint256[](5);
        for (uint256 i = 0; i < opHashes.length; i++) {
            slots[i] = TrailsSentinelLib.successSlot(opHashes[i]);
        }

        // All slots should be different
        for (uint256 i = 0; i < slots.length; i++) {
            for (uint256 j = i + 1; j < slots.length; j++) {
                assertTrue(slots[i] != slots[j], "All slots should be unique");
            }
        }
    }

    function test_SuccessSlot_AssemblyCorrectness() public pure {
        // Test that the assembly implementation is correct by comparing with Solidity equivalent
        bytes32 opHash = keccak256("assembly-test");
        bytes32 namespace = TrailsSentinelLib.SENTINEL_NAMESPACE;

        // Assembly version (from contract)
        uint256 assemblySlot = TrailsSentinelLib.successSlot(opHash);

        // Solidity equivalent
        uint256 soliditySlot = uint256(keccak256(abi.encode(namespace, opHash)));

        assertEq(assemblySlot, soliditySlot, "Assembly should match Solidity keccak256(abi.encode(...))");
    }

    function test_Constants_DoNotChange() public pure {
        // Test that constants are what we expect and don't accidentally change
        assertEq(TrailsSentinelLib.SUCCESS_VALUE, 1, "SUCCESS_VALUE should be 1");

        bytes32 expectedNamespace = keccak256("org.sequence.trails.router.sentinel");
        assertEq(
            TrailsSentinelLib.SENTINEL_NAMESPACE, expectedNamespace, "SENTINEL_NAMESPACE should match expected value"
        );
    }

    function test_SentinelNamespace_Computation() public pure {
        // Test that SENTINEL_NAMESPACE is computed correctly
        bytes32 expected = keccak256("org.sequence.trails.router.sentinel");
        assertEq(TrailsSentinelLib.SENTINEL_NAMESPACE, expected);

        // This should cover the keccak256 computation in the constant declaration
    }

    function test_SuccessValue_IsOne() public pure {
        // Test that SUCCESS_VALUE is exactly 1
        assertEq(TrailsSentinelLib.SUCCESS_VALUE, uint256(1));

        // Test that it's not zero or any other value
        assertTrue(TrailsSentinelLib.SUCCESS_VALUE != 0);
        assertTrue(TrailsSentinelLib.SUCCESS_VALUE != 2);
    }

    function test_SuccessSlot_UsesCorrectNamespace() public pure {
        bytes32 opHash = keccak256("test");

        // Manually compute what the slot should be
        bytes32 expectedSlot = keccak256(abi.encode(TrailsSentinelLib.SENTINEL_NAMESPACE, opHash));

        uint256 actualSlot = TrailsSentinelLib.successSlot(opHash);
        assertEq(actualSlot, uint256(expectedSlot));

        // This ensures the namespace variable assignment is covered
    }
}
