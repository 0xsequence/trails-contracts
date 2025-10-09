// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Deploy as TrailsRouterDeploy} from "script/TrailsRouter.s.sol";
import {TrailsRouter} from "src/TrailsRouter.sol";
import {Create2Utils} from "../utils/Create2Utils.sol";

// -----------------------------------------------------------------------------
// Test Contract
// -----------------------------------------------------------------------------

contract TrailsRouterDeploymentTest is Test {
    // -------------------------------------------------------------------------
    // Test State Variables
    // -------------------------------------------------------------------------

    TrailsRouterDeploy internal _deployScript;
    address internal _deployer;
    uint256 internal _deployerPk;
    string internal _deployerPkStr;

    // -------------------------------------------------------------------------
    // Pure Functions
    // -------------------------------------------------------------------------

    // Expected predetermined address (calculated using CREATE2)
    function expectedRouterAddress() internal pure returns (address payable) {
        return Create2Utils.calculateCreate2Address(type(TrailsRouter).creationCode, Create2Utils.standardSalt());
    }

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        _deployScript = new TrailsRouterDeploy();
        _deployerPk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // anvil default key
        _deployerPkStr = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
        _deployer = vm.addr(_deployerPk);
        vm.deal(_deployer, 100 ether);
    }

    // -------------------------------------------------------------------------
    // Test Functions
    // -------------------------------------------------------------------------

    function test_DeployTrailsRouter_Success() public {
        vm.setEnv("PRIVATE_KEY", _deployerPkStr);

        vm.recordLogs();
        _deployScript.run();

        // Verify TrailsRouter was deployed at the expected address
        address payable expectedAddr = expectedRouterAddress();
        assertEq(expectedAddr.code.length > 0, true, "TrailsRouter should be deployed");

        // Verify the deployed contract is functional
        TrailsRouter router = TrailsRouter(expectedAddr);
        assertEq(address(router).code.length > 0, true, "Router should have code");
    }

    function test_DeployTrailsRouter_SameAddress() public {
        vm.setEnv("PRIVATE_KEY", _deployerPkStr);

        // First deployment
        vm.recordLogs();
        _deployScript.run();

        // Verify first deployment address
        address payable expectedAddr = expectedRouterAddress();
        assertEq(expectedAddr.code.length > 0, true, "First deployment: TrailsRouter deployed");

        // Re-set the PRIVATE_KEY for second deployment
        vm.setEnv("PRIVATE_KEY", _deployerPkStr);

        // Second deployment should result in the same address (deterministic)
        vm.recordLogs();
        _deployScript.run();

        // Verify second deployment still has contract at same address
        assertEq(expectedAddr.code.length > 0, true, "Second deployment: TrailsRouter still deployed");
    }

    function test_DeployedRouter_HasCorrectConfiguration() public {
        vm.setEnv("PRIVATE_KEY", _deployerPkStr);

        // Deploy the script
        _deployScript.run();

        // Get reference to deployed contract
        address payable expectedAddr = expectedRouterAddress();
        TrailsRouter router = TrailsRouter(expectedAddr);

        // Verify contract is deployed and functional
        assertEq(address(router).code.length > 0, true, "Router should have code");

        // Test basic functionality - router should be able to receive calls
        // This is a smoke test to ensure the contract is properly deployed
        (bool success,) = address(router).call("");
        assertEq(success, true, "Router should accept basic calls");
    }
}
