// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {TrailsRelaySapientSigner} from "../src/TrailsRelaySapientSigner.sol";

contract Deploy is SingletonDeployer {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(pk);
        console.log("Deployer Address:", deployerAddress);

        bytes32 salt = bytes32(0);

        // Deploy TrailsRelaySapientSigner
        bytes memory initCode = type(TrailsRelaySapientSigner).creationCode;
        address wrapper = _deployIfNotAlready("TrailsRelaySapientSigner", initCode, salt, pk);

        console.log("TrailsRelaySapientSigner deployed at:", wrapper);
    }
}
