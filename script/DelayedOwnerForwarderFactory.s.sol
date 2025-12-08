// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {DelayedOwnerForwarderFactory} from "../src/forwarder/DelayedOwnerForwarderFactory.sol";

contract Deploy is SingletonDeployer {
    // -------------------------------------------------------------------------
    // Run
    // -------------------------------------------------------------------------

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(privateKey);
        console.log("Deployer Address:", deployerAddress);

        bytes32 salt = bytes32(0);

        bytes memory initCode = type(DelayedOwnerForwarderFactory).creationCode;
        address factory = _deployIfNotAlready("DelayedOwnerForwarderFactory", initCode, salt, privateKey);

        console.log("DelayedOwnerForwarderFactory deployed at:", factory);
    }
}
