// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Deploy as TrailsIntentEntrypointDeploy} from "script/TrailsIntentEntrypoint.s.sol";
import {TrailsIntentEntrypoint} from "src/TrailsIntentEntrypoint.sol";
import {Create2Utils} from "../utils/Create2Utils.sol";

// -----------------------------------------------------------------------------
// Test Contract
// -----------------------------------------------------------------------------

contract TrailsIntentEntrypointDeploymentTest is Test {
    // -------------------------------------------------------------------------
    // Test State Variables
    // -------------------------------------------------------------------------

    TrailsIntentEntrypointDeploy internal _deployScript;
    address internal _deployer;
    uint256 internal _deployerPk;
    string internal _deployerPkStr;

    // -------------------------------------------------------------------------
    // Pure Functions
    // -------------------------------------------------------------------------

    // Expected predetermined address (calculated using CREATE2)
    function expectedIntentEntrypointAddress() internal pure returns (address payable) {
        return
            Create2Utils.calculateCreate2Address(type(TrailsIntentEntrypoint).creationCode, Create2Utils.standardSalt());
    }

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        _deployScript = new TrailsIntentEntrypointDeploy();
        _deployerPk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // anvil default key
        _deployerPkStr = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
        _deployer = vm.addr(_deployerPk);
        vm.deal(_deployer, 100 ether);
    }

    // -------------------------------------------------------------------------
    // Tests
    // -------------------------------------------------------------------------

    function test_DeployIntentEntrypoint_Success() public {
        vm.setEnv("PRIVATE_KEY", _deployerPkStr);

        vm.recordLogs();
        _deployScript.run();

        // Get the expected address
        address payable expectedAddress = expectedIntentEntrypointAddress();

        // Verify the deployed contract is functional
        TrailsIntentEntrypoint entrypoint = TrailsIntentEntrypoint(expectedAddress);
        assertEq(address(entrypoint).code.length > 0, true, "Entrypoint should have code");

        // Verify domain separator is set (basic functionality test)
        bytes32 domainSeparator = entrypoint.DOMAIN_SEPARATOR();
        assertTrue(domainSeparator != bytes32(0), "Domain separator should be set");
    }

    function test_DeployIntentEntrypoint_SameAddress() public {
        vm.setEnv("PRIVATE_KEY", _deployerPkStr);

        // Get the expected address
        address payable expectedAddress = expectedIntentEntrypointAddress();

        // First deployment
        vm.recordLogs();
        _deployScript.run();

        // Verify first deployment address
        assertEq(expectedAddress.code.length > 0, true, "First deployment: TrailsIntentEntrypoint deployed");

        // Re-set the PRIVATE_KEY for second deployment
        vm.setEnv("PRIVATE_KEY", _deployerPkStr);

        // Second deployment should result in the same address (deterministic)
        vm.recordLogs();
        _deployScript.run();

        // Verify second deployment still has contract at same address
        assertEq(expectedAddress.code.length > 0, true, "Second deployment: TrailsIntentEntrypoint still deployed");
    }

    function test_DeployedIntentEntrypoint_HasCorrectConfiguration() public {
        vm.setEnv("PRIVATE_KEY", _deployerPkStr);

        // Deploy the script
        _deployScript.run();

        // Get reference to deployed contract
        address payable expectedAddress = expectedIntentEntrypointAddress();
        TrailsIntentEntrypoint entrypoint = TrailsIntentEntrypoint(expectedAddress);

        // Verify contract is deployed and functional
        assertEq(address(entrypoint).code.length > 0, true, "Entrypoint should have code");

        // Verify EIP-712 domain separator is properly constructed
        bytes32 domainSeparator = entrypoint.DOMAIN_SEPARATOR();
        assertTrue(domainSeparator != bytes32(0), "Domain separator should be initialized");

        // Verify constants are set correctly
        assertEq(entrypoint.VERSION(), "1", "Version should be 1");
        assertTrue(entrypoint.TRAILS_INTENT_TYPEHASH() != bytes32(0), "Intent typehash should be set");

        // Verify contract has expected storage layout by checking usedIntents mapping
        // This is a smoke test that the contract is properly initialized
        bytes32 testIntentHash = keccak256("test");
        assertEq(entrypoint.usedIntents(testIntentHash), false, "usedIntents should be false for unused intent");
    }
}
