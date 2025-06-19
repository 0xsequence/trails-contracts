// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {AnypayRelaySapientSigner} from "../src/AnypayRelaySapientSigner.sol";

contract Deploy is SingletonDeployer {
    // Hardcoded relay solver address
    address constant RELAY_SOLVER = 0xf70da97812CB96acDF810712Aa562db8dfA3dbEF;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(pk);
        console.log("Deployer Address:", deployerAddress);

        bytes32 salt = bytes32(0);

        // Deploy AnypayRelaySapientSigner with hardcoded relay solver address
        bytes memory initCode = abi.encodePacked(type(AnypayRelaySapientSigner).creationCode, abi.encode(RELAY_SOLVER));
        address wrapper = _deployIfNotAlready("AnypayRelaySapientSigner", initCode, salt, pk);

        console.log("AnypayRelaySapientSigner deployed at:", wrapper);
    }
}
