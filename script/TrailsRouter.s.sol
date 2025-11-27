// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {TrailsRouter} from "../src/TrailsRouter.sol";

contract Deploy is SingletonDeployer {
    // -------------------------------------------------------------------------
    // Run
    // -------------------------------------------------------------------------

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(pk);
        console.log("Deployer Address:", deployerAddress);

        address router = deployRouter(pk);
        console.log("TrailsRouter deployed at:", router);
    }

    // -------------------------------------------------------------------------
    // Deploy Router
    // -------------------------------------------------------------------------

    function deployRouter(uint256 pk) public returns (address) {
        bytes32 salt = bytes32(0);
        address multicall3 = 0xcA11bde05977b3631167028862bE2a173976CA11;

        // Deploy TrailsRouter with constructor arguments
        bytes memory initCode = abi.encodePacked(type(TrailsRouter).creationCode, abi.encode(multicall3));
        address router = _deployIfNotAlready("TrailsRouter", initCode, salt, pk);

        return router;
    }
}
