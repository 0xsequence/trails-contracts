// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {TrailsCCTPV2SapientSigner} from "../src/TrailsCCTPV2SapientSigner.sol";

contract Deploy is SingletonDeployer {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(pk);
        console.log("Deployer Address:", deployerAddress);

        address tokenMessengerAddress = vm.envAddress("TOKEN_MESSENGER_ADDRESS");
        console.log("Token Messenger Address:", tokenMessengerAddress);

        bytes32 salt = bytes32(0);

        // Deploy TrailsCCTPV2SapientSigner
        bytes memory initCode =
            abi.encodePacked(type(TrailsCCTPV2SapientSigner).creationCode, abi.encode(tokenMessengerAddress));
        address wrapper = _deployIfNotAlready("TrailsCCTPV2SapientSigner", initCode, salt, pk);

        console.log("TrailsCCTPV2SapientSigner deployed at:", wrapper);
    }
}
