// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {AnypayLiFiInfo} from "@/libraries/AnypayLiFiInterpreter.sol";

/**
 * @title AnypayLifiParams
 * @author Shun Kakinoki
 * @notice Library for handling Anypay LiFi intent parameters, specifically for hashing.
 */
library AnypayLifiParams {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error LifiInfosIsEmpty();
    error AttestationAddressIsZero();

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Generates a unique bytes32 hash for an array of AnypayLiFiInfo.
     * @param lifiInfos An array of LiFi-specific information for the transaction.
     * @param attestationAddress The address used for attestation.
     * @return The keccak256 hash of the LiFi information.
     */
    function getAnypayLiFiInfoHash(AnypayLiFiInfo[] memory lifiInfos, address attestationAddress)
        public
        pure
        returns (bytes32)
    {
        if (lifiInfos.length == 0) revert LifiInfosIsEmpty();
        if (attestationAddress == address(0)) revert AttestationAddressIsZero();
        return keccak256(abi.encode(lifiInfos, attestationAddress));
    }
}
