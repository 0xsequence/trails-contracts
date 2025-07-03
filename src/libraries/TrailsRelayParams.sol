// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {TrailsRelayInfo} from "@/interfaces/TrailsRelay.sol";

/**
 * @title TrailsRelayParams
 * @author Shun Kakinoki
 * @notice Library for handling Trails Relay intent parameters, specifically for hashing.
 */
library TrailsRelayParams {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error RelayInfosIsEmpty();
    error AttestationAddressIsZero();

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Generates a unique bytes32 hash for an array of TrailsRelayInfo.
     * @param relayInfos An array of Relay-specific information for the transaction.
     * @param attestationAddress The address used for attestation.
     * @return The keccak256 hash of the Relay information.
     */
    function getTrailsRelayInfoHash(TrailsRelayInfo[] memory relayInfos, address attestationAddress)
        public
        pure
        returns (bytes32)
    {
        if (relayInfos.length == 0) revert RelayInfosIsEmpty();
        if (attestationAddress == address(0)) revert AttestationAddressIsZero();
        return keccak256(abi.encode(relayInfos, attestationAddress));
    }
}
