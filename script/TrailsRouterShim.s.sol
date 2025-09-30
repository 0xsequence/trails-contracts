// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {TrailsRouterShim} from "../src/TrailsRouterShim.sol";
import {TrailsMulticall3Router} from "../src/TrailsMulticall3Router.sol";

contract Deploy is SingletonDeployer {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(pk);
        console.log("Deployer Address:", deployerAddress);

        bytes32 salt = bytes32(0);

        // First, deploy TrailsMulticall3Router if not already deployed
        bytes memory routerInitCode = type(TrailsMulticall3Router).creationCode;
        address router = _deployIfNotAlready("TrailsMulticall3Router", routerInitCode, salt, pk);
        console.log("TrailsMulticall3Router deployed at:", router);

        // Deploy TrailsRouterShim with the router address
        bytes memory initCode = abi.encodePacked(type(TrailsRouterShim).creationCode, abi.encode(router));
        address wrapper = _deployIfNotAlready("TrailsRouterShim", initCode, salt, pk);

        console.log("TrailsRouterShim deployed at:", wrapper);
    }
}
