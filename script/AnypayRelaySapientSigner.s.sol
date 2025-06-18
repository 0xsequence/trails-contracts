// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {AnypayRelaySapientSigner} from "../src/AnypayRelaySapientSigner.sol";

contract Deploy is SingletonDeployer {
    // Hardcoded LiFiDiamond address
    address constant RELAY_SOLVER = 0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(pk);
        console.log("Deployer Address:", deployerAddress);

        bytes32 salt = bytes32(0);

        // Deploy AnypayRelaySapientSigner with hardcoded LiFiDiamond address
        bytes memory initCode = abi.encodePacked(type(AnypayRelaySapientSigner).creationCode, abi.encode(RELAY_SOLVER));
        address wrapper = _deployIfNotAlready("AnypayRelaySapientSigner", initCode, salt, pk);

        console.log("AnypayRelaySapientSigner deployed at:", wrapper);
    }
}
