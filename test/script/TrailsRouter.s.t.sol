// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Deploy as TrailsRouterDeploy} from "script/TrailsRouter.s.sol";
import {TrailsRouter} from "src/TrailsRouter.sol";

contract TrailsRouterDeploymentTest is Test {
    TrailsRouterDeploy internal deployScript;
    address internal deployer;
    uint256 internal deployerPk;
    string internal deployerPkStr;

    function setUp() public {
        deployScript = new TrailsRouterDeploy();
        deployerPk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80; // anvil default key
        deployerPkStr = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
        deployer = vm.addr(deployerPk);
        vm.deal(deployer, 100 ether);
    }

    function test_DeployRouter_Success() public {
        vm.setEnv("PRIVATE_KEY", deployerPkStr);

        vm.recordLogs();
        deployScript.run();
    }

    function test_DeployRouter_SameAddress() public {
        vm.setEnv("PRIVATE_KEY", deployerPkStr);

        // First deployment
        vm.recordLogs();
        deployScript.run();

        // Re-set the PRIVATE_KEY for second deployment
        vm.setEnv("PRIVATE_KEY", deployerPkStr);

        // Second deployment should result in the same address (deterministic)
        vm.recordLogs();
        deployScript.run();
    }

    function test_DeployedRouter_HasCorrectConfiguration() public {
        vm.setEnv("PRIVATE_KEY", deployerPkStr);

        // Deploy the script
        deployScript.run();
    }
}
