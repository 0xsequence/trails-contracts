// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.30;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {TrailsValidator} from "../src/TrailsValidator.sol";

contract Deploy is SingletonDeployer {
    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(privateKey);
        console.log("Deployer Address:", deployerAddress);

        bytes32 salt = bytes32(0);

        bytes memory initCode = type(TrailsValidator).creationCode;
        address validator = _deployIfNotAlready("TrailsValidator", initCode, salt, privateKey);

        console.log("TrailsValidator deployed at:", validator);
    }
}
