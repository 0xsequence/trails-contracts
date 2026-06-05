// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {OIFSapient} from "src/modules/OIFSapient.sol";

contract DeployOIFSapient is Script {
    function run() external {
        // Trusted signer for quote attestation.
        // Set to deployer as placeholder - redeploy with real aggregator/solver address
        // when OIF quote attestation is live.
        address trustedSigner = msg.sender;

        vm.startBroadcast();

        OIFSapient sapient = new OIFSapient(trustedSigner);

        console.log("OIFSapient deployed at:", address(sapient));
        console.log("  trustedSigner:", address(sapient.trustedSigner()));

        vm.stopBroadcast();
    }
}
