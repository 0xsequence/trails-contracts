// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {TrailsTokenSweeper} from "../src/TrailsTokenSweeper.sol";

contract Deploy is SingletonDeployer {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(privateKey);
        console.log("Deployer Address:", deployerAddress);

        bytes32 salt = bytes32(0);

        // Deploy TrailsTokenSweeper deterministically via ERC-2470 SingletonDeployer
        bytes memory initCode = type(TrailsTokenSweeper).creationCode;
        address sweeper = _deployIfNotAlready("TrailsTokenSweeper", initCode, salt, privateKey);

        console.log("TrailsTokenSweeper deployed at:", sweeper);
    }
}
