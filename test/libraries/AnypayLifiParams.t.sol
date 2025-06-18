// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {AnypayLifiParams} from "@/libraries/AnypayLifiParams.sol";
import {AnypayLiFiInfo} from "@/libraries/AnypayLiFiInterpreter.sol";

contract AnypayLifiParamsTest is Test {
    AnypayLiFiInfo[] internal lifiInfos;
    address internal attestationAddress;

    function setUp() public {
        lifiInfos = new AnypayLiFiInfo[](1);
        lifiInfos[0] = AnypayLiFiInfo({
            originToken: 0x1111111111111111111111111111111111111111,
            amount: 100,
            originChainId: 1,
            destinationChainId: 10
        });

        attestationAddress = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;
    }

    function testGetAnypayLiFiInfoHash_HappyPath() public {
        vm.chainId(1);
        bytes32 hash = AnypayLifiParams.getAnypayLiFiInfoHash(lifiInfos, attestationAddress);
        // This is a snapshot of the expected hash. If the hashing logic changes, this value needs to be updated.
        bytes32 expectedHash = 0x21872bd6b64711c4a5aecba95829c612f0b50c63f1a26991c2f76cf4a754aede;
        assertEq(hash, expectedHash, "LiFi info hash mismatch");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfLifiInfosIsEmpty() public {
        lifiInfos = new AnypayLiFiInfo[](0);
        vm.expectRevert(AnypayLifiParams.LifiInfosIsEmpty.selector);
        AnypayLifiParams.getAnypayLiFiInfoHash(lifiInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfAttestationAddressIsZero() public {
        attestationAddress = address(0);
        vm.expectRevert(AnypayLifiParams.AttestationAddressIsZero.selector);
        AnypayLifiParams.getAnypayLiFiInfoHash(lifiInfos, attestationAddress);
    }
}
