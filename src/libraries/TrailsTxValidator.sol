// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./RLPReader.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

library TrailsTxValidator {

    uint8 constant LEGACY_TX_TYPE = 0x00;
    uint8 constant EIP1559_TX_TYPE = 0x02;

    uint8 constant RLP_ENCODED_R_S_BYTE_SIZE = 66; // 2 * 33bytes (for r, s components)
    uint8 constant EIP_155_MIN_V_VALUE = 37;
    uint8 constant HASH_BYTE_SIZE = 32;

    using RLPReader for RLPReader.RLPItem;
    using RLPReader for bytes;
    using ECDSA for bytes32;

    struct TxData {
        uint8 txType;
        uint8 v;
        bytes32 r;
        bytes32 s;
        bytes32 utxHash; // unsigned tx hash
        bytes32 appendedHash; // extracted bytes32 hash from tx.data
    }

    struct TxParams {
        uint256 v;
        bytes32 r;
        bytes32 s;
        bytes callData;
    }

    /**
     * This function parses the given userOpSignature into a valid fully signed EVM transaction.
     * Once parsed, the function will check for two conditions:
     *      1. is the expected hash found in the tx.data as the last 32bytes?
     *      2. is the recovered tx signer equal to the expected signer?
     * 
     * If both conditions are met - outside contract can be sure that the expected signer has indeed
     * approved the given hash by performing given on-chain transaction.
     * 
     * NOTES: This function will revert if either of following is met:
     *    1. the userOpSignature couldn't be parsed to a valid fully signed EVM transaction
     *    2. hash couldn't be extracted from the tx.data
     *    3. extracted hash wasn't equal to the provided expected hash
     *    4. recovered signer wasn't equal to the expected signer
     * 
     * Returns true if the expected signer did indeed approve the given expectedHash by signing an on-chain transaction.
     * 
     * @param userOpSignature Signature provided as the userOp.signature parameter. Expecting to receive
     *                        fully signed serialized EVM transcaction here of type 0x00 (LEGACY) or 0x02 (EIP1556).
     *                        For LEGACY tx type the "0x00" prefix has to be added manually while the EIP1559 tx type
     *                        already contains 0x02 prefix.
     * @param expectedHash Hash expected to be found as the last 32 bytes appended to the tx data parameter.
     *                     If no hash found exception is thrown.
     * @param expectedSigner Signer expected to be recovered when decoding the signed transaction and recovering the signer.
     */
    function validate(bytes memory userOpSignature, bytes32 expectedHash, address expectedSigner) internal pure returns (bool) {
        TxData memory decodedTx = decodeTx(userOpSignature);
        
        if (decodedTx.appendedHash != expectedHash) {
            revert("TrailsTxValidator:: Extracted hash not equal to the expected appended hash");
        }

        bytes memory signature = abi.encodePacked(decodedTx.r, decodedTx.s, decodedTx.v);
        
        address recovered = MessageHashUtils.toEthSignedMessageHash(decodedTx.utxHash).recover(signature);
        if (expectedSigner != recovered) {
            recovered = decodedTx.utxHash.recover(signature);
            if (expectedSigner != recovered) {
                revert("TrailsTxValidator:: Recovered signer not equal to the expected signer.");
            }
        }

        return true;
    }

    function decodeTx(bytes memory self) private pure returns (TxData memory) {
        uint8 txType = uint8(self[0]); //first byte is tx type
        bytes memory rlpEncodedTx = _slice(self, 1, self.length - 1);
        RLPReader.RLPItem memory parsedRlpEncodedTx = rlpEncodedTx.toRlpItem();
        RLPReader.RLPItem[] memory parsedRlpEncodedTxItems = parsedRlpEncodedTx.toList();
        TxParams memory params = extractParams(txType, parsedRlpEncodedTxItems);        

        return TxData(
            txType,
            _adjustV(params.v),
            params.r,
            params.s,
            calculateUnsignedTxHash(txType, rlpEncodedTx, parsedRlpEncodedTx.payloadLen(), params.v),
            extractAppendedHash(params.callData)
        );
    }

    function extractParams(uint8 txType, RLPReader.RLPItem[] memory items) private pure returns (TxParams memory params) {
        uint8 dataPos;
        uint8 vPos;
        uint8 rPos;
        uint8 sPos;
        
        if (txType == LEGACY_TX_TYPE) {
            dataPos = 5;
            vPos = 6;
            rPos = 7;
            sPos = 8;
        } else if (txType == EIP1559_TX_TYPE) {
            dataPos = 7;
            vPos = 9;
            rPos = 10;
            sPos = 11;
        } else { revert("TrailsTxValidator:: unsupported evm tx type"); }

        return TxParams(
            items[vPos].toUint(),
            bytes32(items[rPos].toUint()),
            bytes32(items[sPos].toUint()),
            items[dataPos].toBytes()
        );
    }

    function extractAppendedHash(bytes memory callData) private pure returns (bytes32 appendedHash) {
        if (callData.length < HASH_BYTE_SIZE) { revert("TrailsTxValidator:: callData length too short"); }
        appendedHash = bytes32(_slice(callData, callData.length - HASH_BYTE_SIZE, HASH_BYTE_SIZE));
    }

    function calculateUnsignedTxHash(uint8 txType, bytes memory rlpEncodedTx, uint256 rlpEncodedTxPayloadLen, uint256 v) private pure returns (bytes32 hash) {
        uint256 totalSignatureSize = RLP_ENCODED_R_S_BYTE_SIZE + _encodeUintLength(v);
        uint256 totalPrefixSize = rlpEncodedTx.length - rlpEncodedTxPayloadLen;
        bytes memory rlpEncodedTxNoSigAndPrefix = _slice(rlpEncodedTx, totalPrefixSize, rlpEncodedTx.length - totalSignatureSize - totalPrefixSize);
        if (txType == EIP1559_TX_TYPE) {
            return keccak256(abi.encodePacked(txType, prependRlpContentSize(rlpEncodedTxNoSigAndPrefix, "")));    
        } else if (txType == LEGACY_TX_TYPE) {
            if (v >= EIP_155_MIN_V_VALUE) {
                return keccak256(
                    prependRlpContentSize(
                        rlpEncodedTxNoSigAndPrefix,
                        abi.encodePacked(
                            _encodeUint(uint256(_extractChainIdFromV(v))),
                            _encodeUint(uint256(0)),
                            _encodeUint(uint256(0))
                        )    
                    ));
            } else {
                return keccak256(prependRlpContentSize(rlpEncodedTxNoSigAndPrefix, ""));
            }
        } else {
            revert("TrailsTxValidator:: unsupported tx type");
        }
    }

    function prependRlpContentSize(bytes memory content, bytes memory extraData) private pure returns (bytes memory) {
        bytes memory combinedContent = abi.encodePacked(content, extraData);
        return abi.encodePacked(_encodeLength(combinedContent.length, RLPReader.LIST_SHORT_START), combinedContent);
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

    // Helper functions for bytes manipulation and RLP encoding
    function _slice(bytes memory data, uint256 start, uint256 length) private pure returns (bytes memory) {
        require(start + length <= data.length, "TrailsTxValidator:: slice out of bounds");
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

    function _encodeUintLength(uint256 value) private pure returns (uint256) {
        if (value == 0) return 1;
        if (value <= 0x7f) return 1;
        
        uint256 length = 0;
        uint256 temp = value;
        while (temp > 0) {
            length++;
            temp = temp >> 8;
        }
        return length + 1; // +1 for the length prefix
    }

    function _encodeUint(uint256 value) private pure returns (bytes memory) {
        if (value == 0) {
            return hex"80";
        }
        if (value <= 0x7f) {
            return abi.encodePacked(uint8(value));
        }
        
        bytes memory result;
        uint256 temp = value;
        uint256 length = 0;
        
        // Calculate length
        while (temp > 0) {
            length++;
            temp = temp >> 8;
        }
        
        result = new bytes(length + 1);
        result[0] = bytes1(uint8(0x80 + length));
        
        // Encode the value
        temp = value;
        for (uint256 i = length; i > 0; i--) {
            result[i] = bytes1(uint8(temp & 0xff));
            temp = temp >> 8;
        }
        
        return result;
    }

    function _encodeLength(uint256 length, uint256 shortStart) private pure returns (bytes memory) {
        if (length < 56) {
            return abi.encodePacked(uint8(shortStart + length));
        } else {
            uint256 lengthOfLength = 0;
            uint256 temp = length;
            while (temp > 0) {
                lengthOfLength++;
                temp = temp >> 8;
            }
            
            bytes memory result = new bytes(lengthOfLength + 1);
            result[0] = bytes1(uint8(shortStart + 55 + lengthOfLength));
            
            temp = length;
            for (uint256 i = lengthOfLength; i > 0; i--) {
                result[i] = bytes1(uint8(temp & 0xff));
                temp = temp >> 8;
            }
            
            return result;
        }
    }

}