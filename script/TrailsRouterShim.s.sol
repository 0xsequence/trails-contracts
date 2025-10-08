// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {TrailsRouterShim} from "../src/TrailsRouterShim.sol";
import {Deploy as TrailsRouterDeploy} from "./TrailsRouter.s.sol";

contract Deploy is SingletonDeployer {
    // -------------------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------------------

    address public routerAddress;

    // -------------------------------------------------------------------------
    // Run
    // -------------------------------------------------------------------------

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(pk);
        console.log("Deployer Address:", deployerAddress);

        bytes32 salt = bytes32(0);

        // Deploy TrailsRouter using the TrailsRouter deployment script
        TrailsRouterDeploy routerDeploy = new TrailsRouterDeploy();
        routerDeploy.run();

        // Get the deployed router address from the deployment script
        routerAddress = routerDeploy.deployRouter(pk);
        console.log("TrailsRouter deployed at:", routerAddress);

        // Deploy TrailsRouterShim with the router address
        bytes memory initCode = abi.encodePacked(type(TrailsRouterShim).creationCode, abi.encode(routerAddress));
        address wrapper = _deployIfNotAlready("TrailsRouterShim", initCode, salt, pk);

        console.log("TrailsRouterShim deployed at:", wrapper);
    }
}
