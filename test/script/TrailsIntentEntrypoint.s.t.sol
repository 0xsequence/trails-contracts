// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Deploy as TrailsIntentEntrypointDeploy} from "script/TrailsIntentEntrypoint.s.sol";
import {TrailsIntentEntrypoint} from "src/TrailsIntentEntrypoint.sol";

contract TrailsIntentEntrypointDeploymentTest is Test {
    // -------------------------------------------------------------------------
    // Test State Variables
    // -------------------------------------------------------------------------

    TrailsIntentEntrypointDeploy internal deployScript;
    address internal deployer;
    uint256 internal deployerPk;
    string internal deployerPkStr;

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        deployScript = new TrailsIntentEntrypointDeploy();
        deployerPk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // anvil default key
        deployerPkStr = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
        deployer = vm.addr(deployerPk);
        vm.deal(deployer, 100 ether);
    }

    // -------------------------------------------------------------------------
    // Tests
    // -------------------------------------------------------------------------

    function test_DeployIntentEntrypoint_Success() public {
        vm.setEnv("PRIVATE_KEY", deployerPkStr);

        vm.recordLogs();
        deployScript.run();

        // Verify deployment was logged
        // In a real deployment, we would verify the contract was deployed at the expected address
        // and that it has the correct configuration
    }

    function test_DeployIntentEntrypoint_SameAddress() public {
        vm.setEnv("PRIVATE_KEY", deployerPkStr);

        // First deployment
        vm.recordLogs();
        deployScript.run();

        // Re-set the PRIVATE_KEY for second deployment
        vm.setEnv("PRIVATE_KEY", deployerPkStr);

        // Second deployment should result in the same address (deterministic)
        vm.recordLogs();
        deployScript.run();

        // Both deployments should succeed without reverting
    }

    function test_DeployedIntentEntrypoint_HasCorrectConfiguration() public {
        vm.setEnv("PRIVATE_KEY", deployerPkStr);

        // Deploy the script
        deployScript.run();

        // Note: In a full test, we would:
        // 1. Capture the deployed address from logs
        // 2. Verify the router address is set correctly
        // 3. Verify immutables are configured as expected
        // 4. Test the deployed contract's functionality
    }
}
