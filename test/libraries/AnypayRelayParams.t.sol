// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {AnypayRelayParams} from "@/libraries/AnypayRelayParams.sol";
import {AnypayRelayInfo} from "@/interfaces/AnypayRelay.sol";

contract AnypayRelayParamsTest is Test {
    AnypayRelayInfo[] internal relayInfos;
    address internal attestationAddress;

    function setUp() public {
        relayInfos = new AnypayRelayInfo[](1);
        relayInfos[0] = AnypayRelayInfo({
            requestId: 0x0000000000000000000000000000000000000000000000000000000000000001,
            signature: hex"abcd",
            nonEVMReceiver: 0x0000000000000000000000000000000000000000000000000000000000000002,
            receivingAssetId: 0x0000000000000000000000000000000000000000000000000000000000000003,
            sendingAssetId: 0x5555555555555555555555555555555555555555,
            receiver: 0x6666666666666666666666666666666666666666,
            destinationChainId: 137,
            minAmount: 1000,
            target: 0x7777777777777777777777777777777777777777
        });

        attestationAddress = 0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa;
    }

    function testGetAnypayRelayInfoHash_HappyPath() public {
        vm.chainId(1);
        bytes32 hash = AnypayRelayParams.getAnypayRelayInfoHash(relayInfos, attestationAddress);
        // This is a snapshot of the expected hash. If the hashing logic changes, this value needs to be updated.
        bytes32 expectedHash = 0x34b1669f0dccfb1e185ee9012c92a17c8548dc504d7a3dc0fedf08522c8c5a63;
        assertEq(hash, expectedHash, "Relay info hash mismatch");
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfRelayInfosIsEmpty() public {
        relayInfos = new AnypayRelayInfo[](0);
        vm.expectRevert(AnypayRelayParams.RelayInfosIsEmpty.selector);
        AnypayRelayParams.getAnypayRelayInfoHash(relayInfos, attestationAddress);
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testRevertIfAttestationAddressIsZero() public {
        attestationAddress = address(0);
        vm.expectRevert(AnypayRelayParams.AttestationAddressIsZero.selector);
        AnypayRelayParams.getAnypayRelayInfoHash(relayInfos, attestationAddress);
    }
}
