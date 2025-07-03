// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {TrailsExecutionInfo} from "@/interfaces/TrailsExecutionInfo.sol";

/**
 * @title TrailsExecutionInfoParams
 * @author Shun Kakinoki
 * @notice Library for handling Trails ExecutionInfo intent parameters, specifically for hashing.
 */
library TrailsExecutionInfoParams {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error ExecutionInfosIsEmpty();
    error AttestationAddressIsZero();

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Generates a unique bytes32 hash for an array of TrailsExecutionInfo.
     * @param executionInfos An array of ExecutionInfo-specific information for the transaction.
     * @param attestationAddress The address used for attestation.
     * @return The keccak256 hash of the ExecutionInfo information.
     */
    function getTrailsExecutionInfoHash(TrailsExecutionInfo[] memory executionInfos, address attestationAddress)
        internal
        pure
        returns (bytes32)
    {
        if (executionInfos.length == 0) revert ExecutionInfosIsEmpty();
        if (attestationAddress == address(0)) revert AttestationAddressIsZero();
        return keccak256(abi.encode(executionInfos, attestationAddress));
    }
}
