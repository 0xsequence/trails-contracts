// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {TrailsRouter} from "../src/TrailsRouter.sol";
import {MULTICALL3_ADDRESS} from "../test/mocks/MockMulticall3.sol";

contract Deploy is SingletonDeployer {
    // -------------------------------------------------------------------------
    // Run
    // -------------------------------------------------------------------------

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(pk);
        console.log("Deployer Address:", deployerAddress);

        address multicall3 = vm.envOr("MULTICALL3_ADDRESS", MULTICALL3_ADDRESS);
        console.log("Multicall3 Address:", multicall3);

        address router = deployRouter(pk, multicall3);
        console.log("TrailsRouter deployed at:", router);
    }

    // -------------------------------------------------------------------------
    // Deploy Router
    // -------------------------------------------------------------------------

    function deployRouter(uint256 pk, address multicall3) public returns (address) {
        bytes32 salt = bytes32(0);

        // Deploy TrailsRouter
        bytes memory initCode = abi.encodePacked(type(TrailsRouter).creationCode, abi.encode(multicall3));
        address router = _deployIfNotAlready("TrailsRouter", initCode, salt, pk);

        return router;
    }
}
