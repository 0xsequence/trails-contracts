// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {CCTPExecutionInfo} from "../interfaces/TrailsCCTPV2.sol";

/**
 * @title TrailsCCTPV2Params
 * @author Shun Kakinoki
 * @notice Library for handling Trails CCTP V2 intent parameters, specifically for hashing.
 */
library TrailsCCTPV2Params {
    error ExecutionInfosIsEmpty();
    error AttestationAddressIsZero();

    /**
     * @notice Generates a unique bytes32 hash for an array of CCTPExecutionInfo.
     * @param executionInfos An array of CCTPExecutionInfo-specific information for the transaction.
     * @param attestationAddress The address used for attestation.
     * @return The keccak256 hash of the CCTPExecutionInfo information.
     */
    function getCCTPExecutionInfoHash(CCTPExecutionInfo[] memory executionInfos, address attestationAddress)
        internal
        pure
        returns (bytes32)
    {
        if (executionInfos.length == 0) revert ExecutionInfosIsEmpty();
        if (attestationAddress == address(0)) revert AttestationAddressIsZero();
        return keccak256(abi.encode(executionInfos, attestationAddress));
    }
}
