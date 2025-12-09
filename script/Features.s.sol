// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {SweepFeature} from "../src/features/SweepFeature.sol";

contract Deploy is SingletonDeployer {
    // -------------------------------------------------------------------------
    // Run
    // -------------------------------------------------------------------------

    function run() external {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(privateKey);
        console.log("Deployer Address:", deployerAddress);

        bytes32 salt = bytes32(0);

        bytes memory initCode = type(SweepFeature).creationCode;
        address sweepFeature = _deployIfNotAlready("SweepFeature", initCode, salt, privateKey);

        console.log("SweepFeature deployed at:", sweepFeature);
    }
}
