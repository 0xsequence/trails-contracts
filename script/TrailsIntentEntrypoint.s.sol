// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {TrailsIntentEntrypoint} from "../src/TrailsIntentEntrypoint.sol";

contract Deploy is SingletonDeployer {
    // -------------------------------------------------------------------------
    // Run
    // -------------------------------------------------------------------------

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(privateKey);
        console.log("Deployer Address:", deployerAddress);

        bytes32 salt = bytes32(0);

        // Deploy TrailsIntentEntrypoint deterministically via ERC-2470 SingletonDeployer
        bytes memory initCode = type(TrailsIntentEntrypoint).creationCode;
        address sweeper = _deployIfNotAlready("TrailsIntentEntrypoint", initCode, salt, privateKey);

        console.log("TrailsIntentEntrypoint deployed at:", sweeper);
    }
}
