// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {PausableSapient} from "src/pausable/PausableSapient.sol";

contract DeployPausableSapient is Script {
    function run() external {
        address owner = msg.sender;
        address[] memory operators = new address[](1);
        operators[0] = owner;

        vm.startBroadcast();

        PausableSapient sapient = new PausableSapient(owner, operators);

        console.log("PausableSapient deployed at:", address(sapient));
        console.log("  owner:", owner);
        console.log("  paused:", sapient.paused());

        vm.stopBroadcast();
    }
}
