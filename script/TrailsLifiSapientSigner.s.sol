// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {TrailsLiFiSapientSigner} from "../src/TrailsLiFiSapientSigner.sol";

contract Deploy is SingletonDeployer {
    // Hardcoded LiFiDiamond address
    address constant LIFI_DIAMOND = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(pk);
        console.log("Deployer Address:", deployerAddress);

        bytes32 salt = bytes32(0);

        // Deploy TrailsLiFiSapientSigner with hardcoded LiFiDiamond address
        bytes memory initCode = abi.encodePacked(type(TrailsLiFiSapientSigner).creationCode, abi.encode(LIFI_DIAMOND));
        address wrapper = _deployIfNotAlready("TrailsLiFiSapientSigner", initCode, salt, pk);

        console.log("TrailsLiFiSapientSigner deployed at:", wrapper);
    }
}
