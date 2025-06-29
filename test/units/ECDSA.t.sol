// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract ECDSAUnitTest is Test {
    function test_ECDSARecover_WithProvidedSignature() public view {
        bytes32 digestToSign = 0x7958624793172ae9de69eb14fcd92a0fe56af7d6de90dab01d6bb4980ecb4e4e;
        bytes memory rawSignature =
            hex"9c34b6bcc8b8de17804978e4bc9e3a4aadcc7d7c6178fae047e79efcd43be80d3e6b3c75676e4e1982c86199cf27ca09b475a2b66ba0491ecbbe58018dd2ca2a1b";

        address expectedSigner = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        address recoveredAddress = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(digestToSign), rawSignature);

        assertEq(recoveredAddress, expectedSigner, "Recovered address does not match expected address");
    }
}
