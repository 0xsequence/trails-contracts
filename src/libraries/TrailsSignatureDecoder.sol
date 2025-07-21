// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library TrailsSignatureDecoder {

    enum UserOpSignatureType {
        OFF_CHAIN,
        ON_CHAIN,
        ERC20_PERMIT
    }

    uint8 constant SIG_TYPE_OFF_CHAIN = 0x00;
    uint8 constant SIG_TYPE_ON_CHAIN = 0x01;
    uint8 constant SIG_TYPE_ERC20_PERMIT = 0x02;

    struct UserOpSignature {
        UserOpSignatureType signatureType;
        bytes signature;
    }

    /**
     * Decodes the signature type and extracts the actual signature data
     * @param self The encoded signature with type prefix
     * @return UserOpSignature struct containing the type and signature data
     */
    function decodeSignature(bytes memory self) internal pure returns (UserOpSignature memory) {
        require(self.length > 0, "TrailsSignatureDecoder:: empty signature");
        
        bytes memory sig = _slice(self, 1, self.length - 1);
        uint8 sigType = uint8(self[0]);
        
        if (sigType == SIG_TYPE_OFF_CHAIN) {
            return UserOpSignature(
                UserOpSignatureType.OFF_CHAIN,
                sig
            );
        } else if (sigType == SIG_TYPE_ON_CHAIN) {
            return UserOpSignature(
                UserOpSignatureType.ON_CHAIN,
                sig
            );
        } else if (sigType == SIG_TYPE_ERC20_PERMIT) {
            return UserOpSignature(
                UserOpSignatureType.ERC20_PERMIT,
                sig
            );
        } else {
            revert("TrailsSignatureDecoder:: invalid userOp sig type. Expected prefix 0x00 for off-chain, 0x01 for on-chain or 0x02 for erc20 permit signature.");
        }
    }

    /**
     * Helper function to slice bytes array
     * @param data The source bytes array
     * @param start Starting index
     * @param length Length of the slice
     * @return result The sliced bytes array
     */
    function _slice(bytes memory data, uint256 start, uint256 length) private pure returns (bytes memory) {
        require(start + length <= data.length, "TrailsSignatureDecoder:: slice out of bounds");
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = data[start + i];
        }
        return result;
    }

}