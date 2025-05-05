// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {SingletonDeployer, console} from "erc2470-libs/script/SingletonDeployer.s.sol";
import {DiamondCutFacet} from "lifi-contracts/Facets/DiamondCutFacet.sol";
import {LiFiDiamond} from "lifi-contracts/LiFiDiamond.sol";
import {AnypayLifiModifierWrapper} from "src/AnypayLifiModifierWrapper.sol";

contract Deploy is SingletonDeployer {
    // Hardcoded LiFiDiamond address
    address constant LIFI_DIAMOND = 0x000000000000000000000000000000000000dEaD;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        bytes32 salt = bytes32(0);

        // Deploy AnypayLifiModifierWrapper with hardcoded LiFiDiamond address
        bytes memory initCode = abi.encodePacked(type(AnypayLifiModifierWrapper).creationCode, abi.encode(LIFI_DIAMOND));
        address wrapper = _deployIfNotAlready("AnypayLifiModifierWrapper", initCode, salt, pk);

        console.log("AnypayLifiModifierWrapper deployed at:", wrapper);
    }
}
