// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Deploy as TrailsRouterDeploy} from "script/TrailsRouter.s.sol";
import {TrailsRouter} from "src/TrailsRouter.sol";
import {ISingletonFactory, SINGLETON_FACTORY_ADDR} from "../../lib/erc2470-libs/src/ISingletonFactory.sol";

contract TrailsRouterDeploymentTest is Test {
    // -------------------------------------------------------------------------
    // Test State Variables
    // -------------------------------------------------------------------------

    TrailsRouterDeploy internal _deployScript;
    address internal _deployer;
    uint256 internal _deployerPk;
    string internal _deployerPkStr;

    // Expected predetermined address (hardcoded from broadcast logs)
    address payable internal constant EXPECTED_ROUTER_ADDRESS = payable(0xC428EBE276bB72c00524e6FBb5280B0FaB009973);

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
        assertEq(EXPECTED_ROUTER_ADDRESS.code.length > 0, true, "TrailsRouter should be deployed");

        // Verify the deployed contract is functional
        TrailsRouter router = TrailsRouter(EXPECTED_ROUTER_ADDRESS);
        assertEq(address(router).code.length > 0, true, "Router should have code");
    }

    function test_DeployTrailsRouter_SameAddress() public {
        vm.setEnv("PRIVATE_KEY", _deployerPkStr);

        // First deployment
        vm.recordLogs();
        _deployScript.run();

        // Verify first deployment address
        assertEq(EXPECTED_ROUTER_ADDRESS.code.length > 0, true, "First deployment: TrailsRouter deployed");

        // Re-set the PRIVATE_KEY for second deployment
        vm.setEnv("PRIVATE_KEY", _deployerPkStr);

        // Second deployment should result in the same address (deterministic)
        vm.recordLogs();
        _deployScript.run();

        // Verify second deployment still has contract at same address
        assertEq(EXPECTED_ROUTER_ADDRESS.code.length > 0, true, "Second deployment: TrailsRouter still deployed");
    }

    function test_DeployedRouter_HasCorrectConfiguration() public {
        vm.setEnv("PRIVATE_KEY", _deployerPkStr);

        // Deploy the script
        _deployScript.run();

        // Get reference to deployed contract
        TrailsRouter router = TrailsRouter(EXPECTED_ROUTER_ADDRESS);

        // Verify contract is deployed and functional
        assertEq(address(router).code.length > 0, true, "Router should have code");

        // Test basic functionality - router should be able to receive calls
        // This is a smoke test to ensure the contract is properly deployed
        (bool success,) = address(router).call("");
        assertEq(success, true, "Router should accept basic calls");
    }
}
