// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {AnypayRelaySapientSigner} from "../src/AnypayRelaySapientSigner.sol";

contract Deploy is SingletonDeployer {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(pk);
        console.log("Deployer Address:", deployerAddress);

        bytes32 salt = bytes32(0);

        // Deploy AnypayRelaySapientSigner
        bytes memory initCode = type(AnypayRelaySapientSigner).creationCode;
        address wrapper = _deployIfNotAlready("AnypayRelaySapientSigner", initCode, salt, pk);

        console.log("AnypayRelaySapientSigner deployed at:", wrapper);
    }
}
