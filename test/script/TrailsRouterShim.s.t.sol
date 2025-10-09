// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Deploy as TrailsRouterShimDeploy} from "script/TrailsRouterShim.s.sol";
import {TrailsRouterShim} from "src/TrailsRouterShim.sol";
import {TrailsRouter} from "src/TrailsRouter.sol";
import {Create2Utils} from "../utils/Create2Utils.sol";

// -----------------------------------------------------------------------------
// Test Contract
// -----------------------------------------------------------------------------

contract TrailsRouterShimDeploymentTest is Test {
    // -------------------------------------------------------------------------
    // Test State Variables
    // -------------------------------------------------------------------------

    TrailsRouterShimDeploy internal _deployScript;
    address internal _deployer;
    uint256 internal _deployerPk;
    string internal _deployerPkStr;

    // -------------------------------------------------------------------------
    // Pure Functions
    // -------------------------------------------------------------------------

    // Expected predetermined addresses (calculated using CREATE2)
    function expectedRouterAddress() internal pure returns (address payable) {
        return Create2Utils.calculateCreate2Address(type(TrailsRouter).creationCode, Create2Utils.standardSalt());
    }

    function expectedShimAddress() internal pure returns (address payable) {
        address routerAddr = expectedRouterAddress();
        bytes memory shimInitCode = abi.encodePacked(type(TrailsRouterShim).creationCode, abi.encode(routerAddr));
        return Create2Utils.calculateCreate2Address(shimInitCode, Create2Utils.standardSalt());
    }

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        _deployScript = new TrailsRouterShimDeploy();
        _deployerPk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // anvil default key
        _deployerPkStr = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
        _deployer = vm.addr(_deployerPk);
        vm.deal(_deployer, 100 ether);
    }

    // -------------------------------------------------------------------------
    // Test Functions
    // -------------------------------------------------------------------------

    function test_DeployRouterShim_Success() public {
        vm.setEnv("PRIVATE_KEY", _deployerPkStr);

        vm.recordLogs();
        _deployScript.run();

        // Get the actual router address from the deployment script
        address deployedRouterAddr = _deployScript.routerAddress();

        // Verify TrailsRouter was deployed
        assertEq(deployedRouterAddr.code.length > 0, true, "TrailsRouter should be deployed");

        // Verify TrailsRouterShim was deployed at the expected address
        address payable expectedShimAddr = expectedShimAddress();
        assertEq(expectedShimAddr.code.length > 0, true, "TrailsRouterShim should be deployed at expected address");

        // Verify the shim's router address is correctly set
        TrailsRouterShim shim = TrailsRouterShim(expectedShimAddr);
        assertEq(address(shim.ROUTER()), deployedRouterAddr, "Shim should have correct router address");
    }

    function test_DeployRouterShim_SameAddress() public {
        vm.setEnv("PRIVATE_KEY", _deployerPkStr);

        // First deployment
        vm.recordLogs();
        _deployScript.run();

        // Get the actual router address from the deployment script
        address deployedRouterAddr = _deployScript.routerAddress();

        // Verify first deployment addresses
        assertEq(deployedRouterAddr.code.length > 0, true, "First deployment: TrailsRouter deployed");
        address payable expectedShimAddr = expectedShimAddress();
        assertEq(expectedShimAddr.code.length > 0, true, "First deployment: TrailsRouterShim deployed");

        // Re-set the PRIVATE_KEY for second deployment
        vm.setEnv("PRIVATE_KEY", _deployerPkStr);

        // Second deployment should result in the same address (deterministic)
        vm.recordLogs();
        _deployScript.run();

        // Verify second deployment still has contracts at same addresses
        assertEq(deployedRouterAddr.code.length > 0, true, "Second deployment: TrailsRouter still deployed");
        assertEq(expectedShimAddr.code.length > 0, true, "Second deployment: TrailsRouterShim still deployed");

        // Both deployments should succeed without reverting
    }

    function test_DeployedContract_HasCorrectConfiguration() public {
        vm.setEnv("PRIVATE_KEY", _deployerPkStr);

        // Deploy the script
        _deployScript.run();

        // Get references to deployed contracts
        address deployedRouterAddr = _deployScript.routerAddress();
        address payable expectedShimAddr = expectedShimAddress();
        TrailsRouterShim shim = TrailsRouterShim(expectedShimAddr);
        TrailsRouter router = TrailsRouter(payable(deployedRouterAddr));

        // Verify the router address is set correctly in the shim
        assertEq(address(shim.ROUTER()), deployedRouterAddr, "Shim should have correct router address set");

        // Verify router is properly initialized (basic smoke test)
        assertEq(address(router).code.length > 0, true, "Router should have code");

        // Test that the shim can access its router (basic functionality test)
        // This tests that the immutable is correctly set and accessible
        address routerFromShim = address(shim.ROUTER());
        assertEq(routerFromShim, deployedRouterAddr, "Shim should be able to access its router address");
    }
}
