// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {AnypayExecutionInfoParams} from "@/libraries/AnypayExecutionInfoParams.sol";
import {AnypayExecutionInfo} from "@/interfaces/AnypayExecutionInfo.sol";

contract AnypayExecutionInfoParamsTest is Test {
    AnypayExecutionInfo[] internal lifiInfos;
    address internal attestationAddress;

    function setUp() public {
        lifiInfos = new AnypayExecutionInfo[](1);
        lifiInfos[0] = AnypayExecutionInfo({
            originToken: 0x1111111111111111111111111111111111111111,
            amount: 100,
            originChainId: 1,
            destinationChainId: 10
        });

        attestationAddress = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;
    }

    function testGetAnypayExecutionInfoHash_HappyPath() public {
        vm.chainId(1);
        bytes32 hash = AnypayExecutionInfoParams.getAnypayExecutionInfoHash(lifiInfos, attestationAddress);
        // This is a snapshot of the expected hash. If the hashing logic changes, this value needs to be updated.
        bytes32 expectedHash = 0x21872bd6b64711c4a5aecba95829c612f0b50c63f1a26991c2f76cf4a754aede;
        assertEq(hash, expectedHash, "LiFi info hash mismatch");
    }

    function testGetAnypayExecutionInfoHash_WithUserParams() public pure {
        AnypayExecutionInfo[] memory executionInfos = new AnypayExecutionInfo[](1);
        executionInfos[0] = AnypayExecutionInfo({
            originToken: 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9,
            amount: 1052844,
            originChainId: 42161,
            destinationChainId: 8453
        });
        address attestationSigner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        bytes32 hash = AnypayExecutionInfoParams.getAnypayExecutionInfoHash(executionInfos, attestationSigner);
        bytes32 expectedHash = 0x98f9389e78aafff240a62ffbfdd16c3beee1932f5b90e0cfaa90c74c004f4645;
        assertEq(hash, expectedHash, "AnypayExecutionInfo hash mismatch with user params");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfLifiInfosIsEmpty() public {
        lifiInfos = new AnypayExecutionInfo[](0);
        vm.expectRevert(AnypayExecutionInfoParams.ExecutionInfosIsEmpty.selector);
        AnypayExecutionInfoParams.getAnypayExecutionInfoHash(lifiInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfAttestationAddressIsZero() public {
        attestationAddress = address(0);
        vm.expectRevert(AnypayExecutionInfoParams.AttestationAddressIsZero.selector);
        AnypayExecutionInfoParams.getAnypayExecutionInfoHash(lifiInfos, attestationAddress);
    }
}
