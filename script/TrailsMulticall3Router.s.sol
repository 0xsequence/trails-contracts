// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {TrailsMulticall3Router} from "../src/TrailsMulticall3Router.sol";

contract Deploy is SingletonDeployer {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(pk);
        console.log("Deployer Address:", deployerAddress);

        bytes32 salt = bytes32(0);

        // Deploy TrailsMulticall3Router
        bytes memory initCode = type(TrailsMulticall3Router).creationCode;
        address wrapper = _deployIfNotAlready("TrailsMulticall3Router", initCode, salt, pk);

        console.log("TrailsMulticall3Router deployed at:", wrapper);
    }
}
