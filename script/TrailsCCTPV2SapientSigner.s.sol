// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {TrailsCCTPV2SapientSigner} from "../src/TrailsCCTPV2SapientSigner.sol";

contract Deploy is SingletonDeployer {
    // From: https://developers.circle.com/stablecoins/evm-smart-contracts
    address constant TOKEN_MESSENGER_ADDRESS = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(pk);
        console.log("Deployer Address:", deployerAddress);

        bytes32 salt = bytes32(0);

        // Deploy TrailsCCTPV2SapientSigner
        bytes memory initCode =
            abi.encodePacked(type(TrailsCCTPV2SapientSigner).creationCode, abi.encode(TOKEN_MESSENGER_ADDRESS));
        address wrapper = _deployIfNotAlready("TrailsCCTPV2SapientSigner", initCode, salt, pk);

        console.log("TrailsCCTPV2SapientSigner deployed at:", wrapper);
    }
}
