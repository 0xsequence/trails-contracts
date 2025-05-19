// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {AnypayLifiSapientSigner} from "../src/AnypayLifiSapientSigner.sol";

contract Deploy is SingletonDeployer {
    // Hardcoded LiFiDiamond address
    address constant LIFI_DIAMOND = 0x000000000000000000000000000000000000dEaD;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        bytes32 salt = bytes32(0);

        // Deploy AnypayLifiSapientSigner with hardcoded LiFiDiamond address
        bytes memory initCode = abi.encodePacked(type(AnypayLifiSapientSigner).creationCode, abi.encode(LIFI_DIAMOND));
        address wrapper = _deployIfNotAlready("AnypayLifiSapientSigner", initCode, salt, pk);

        console.log("AnypayLifiSapientSigner deployed at:", wrapper);
    }
}
