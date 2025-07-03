// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {CCTPExecutionInfo} from "../interfaces/TrailsCCTPV2.sol";

/**
 * @title TrailsCCTPV2Validator
 * @author Shun Kakinoki
 * @notice Library for validating Trails CCTP V2 data.
 */
library TrailsCCTPV2Validator {
    error MismatchedAttestationLength();
    error InvalidAttestation();

    /**
     * @notice Validates that each attested CCTPExecutionInfo struct matches the corresponding inferred CCTPExecutionInfo struct.
     * @param inferredExecutionInfos Array of CCTPExecutionInfo structs inferred from current transaction data.
     * @param attestedExecutionInfos Array of CCTPExecutionInfo structs derived from attestations.
     */
    function validateExecutionInfos(
        CCTPExecutionInfo[] memory inferredExecutionInfos,
        CCTPExecutionInfo[] memory attestedExecutionInfos
    ) internal pure returns (bool) {
        if (inferredExecutionInfos.length != attestedExecutionInfos.length) {
            revert MismatchedAttestationLength();
        }

        for (uint256 i = 0; i < inferredExecutionInfos.length; i++) {
            if (keccak256(abi.encode(inferredExecutionInfos[i])) != keccak256(abi.encode(attestedExecutionInfos[i]))) {
                revert InvalidAttestation();
            }
        }

        return true;
    }
}
