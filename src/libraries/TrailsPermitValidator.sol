// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// Interface for ERC20 tokens with permit functionality
interface IERC20Permit {
    function PERMIT_TYPEHASH() external view returns (bytes32);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
}

library TrailsPermitValidator {
    uint8 constant EIP_155_MIN_V_VALUE = 37;

    using ECDSA for bytes32;

    struct DecodedErc20PermitSig {
        IERC20Permit token;
        uint256 amount;
        uint256 chainId;
        uint256 nonce;
        bool isPermitTx;
        bytes32 appendedHash;
        uint256 v;
        bytes32 r;
        bytes32 s;
    }

    /**
     * This function parses the given userOpSignature into a DecodedErc20PermitSig data structure.
     *
     * Once parsed, the function will check for two conditions:
     *      1. is the expected hash found in the signed Permit message's deadline field?
     *      2. is the recovered message signer equal to the expected signer?
     *
     * If both conditions are met - outside contract can be sure that the expected signer has indeed
     * approved the given hash by signing a given Permit message.
     *
     * NOTES: This function will revert if either of following is met:
     *    1. the userOpSignature couldn't be abi.decoded into a valid DecodedErc20PermitSig struct as defined in this contract
     *    2. extracted hash wasn't equal to the provided expected hash
     *    3. recovered Permit message signer wasn't equal to the expected signer
     *
     * Returns true if the expected signer did indeed approve the given expectedHash by signing an on-chain transaction.
     * In that case, the function will also perform the Permit approval on the given token in case the
     * isPermitTx flag was set to true in the decoded signature struct.
     *
     * @param userOpSignature Signature provided as the userOp.signature parameter. Expecting to receive
     *                        abi.encoded DecodedErc20PermitSig struct.
     * @param userOpSender UserOp sender
     * @param expectedHash Hash expected to be found as the deadline in the permit message.
     *                     If no hash found exception is thrown.
     * @param expectedSigner Signer expected to be recovered when decoding the signed permit and recovering the signer.
     */
    function validate(bytes memory userOpSignature, address userOpSender, bytes32 expectedHash, address expectedSigner)
        internal
        returns (bool)
    {
        DecodedErc20PermitSig memory decodedSig = abi.decode(userOpSignature, (DecodedErc20PermitSig));

        if (decodedSig.appendedHash != expectedHash) {
            revert("TrailsPermitValidator:: Extracted data hash not equal to the expected data hash.");
        }

        uint8 vAdjusted = _adjustV(decodedSig.v);
        uint256 deadline = uint256(decodedSig.appendedHash);

        bytes32 structHash = keccak256(
            abi.encode(
                decodedSig.token.PERMIT_TYPEHASH(),
                expectedSigner,
                userOpSender,
                decodedSig.amount,
                decodedSig.nonce,
                deadline
            )
        );

        bytes32 signedDataHash = _hashTypedDataV4(structHash, decodedSig.token.DOMAIN_SEPARATOR());
        bytes memory signature = abi.encodePacked(decodedSig.r, decodedSig.s, vAdjusted);

        address recovered = MessageHashUtils.toEthSignedMessageHash(signedDataHash).recover(signature);
        if (expectedSigner != recovered) {
            recovered = signedDataHash.recover(signature);
            if (expectedSigner != recovered) {
                revert("TrailsPermitValidator:: recovered signer not equal to the expected signer");
            }
        }

        if (decodedSig.isPermitTx) {
            decodedSig.token.permit(
                expectedSigner, userOpSender, decodedSig.amount, deadline, vAdjusted, decodedSig.r, decodedSig.s
            );
        }

        return true;
    }

    function _hashTypedDataV4(bytes32 structHash, bytes32 domainSeparator) private pure returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(domainSeparator, structHash);
    }

    function _adjustV(uint256 v) private pure returns (uint8) {
        if (v >= EIP_155_MIN_V_VALUE) {
            return uint8((v - 2 * _extractChainIdFromV(v) - 35) + 27);
        } else if (v <= 1) {
            return uint8(v + 27);
        } else {
            return uint8(v);
        }
    }

    function _extractChainIdFromV(uint256 v) private pure returns (uint256 chainId) {
        chainId = (v - 35) / 2;
    }
}
