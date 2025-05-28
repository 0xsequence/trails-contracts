// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
// import {AnypayLiFiSapientSigner} from "../src/AnypayLiFiSapientSigner.sol";
import {AnypayLiFiSapientSignerLite} from "../src/AnypayLiFiSapientSigner.sol";

contract Deploy is SingletonDeployer {
    // Hardcoded LiFiDiamond address
    address constant LIFI_DIAMOND = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(pk);
        console.log("Deployer Address:", deployerAddress);

        bytes32 salt = bytes32(0);

        // Deploy AnypayLiFiSapientSigner with hardcoded LiFiDiamond address
        // bytes memory initCode = abi.encodePacked(type(AnypayLiFiSapientSigner).creationCode, abi.encode(LIFI_DIAMOND));
        bytes memory initCode =
            abi.encodePacked(type(AnypayLiFiSapientSignerLite).creationCode, abi.encode(LIFI_DIAMOND));
        address wrapper = _deployIfNotAlready("AnypayLiFiSapientSigner", initCode, salt, pk);

        console.log("AnypayLiFiSapientSigner deployed at:", wrapper);
    }
}
