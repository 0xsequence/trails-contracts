// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CCTPExecutionInfo, ITokenMessengerV2} from "@/interfaces/TrailsCCTPV2.sol";

/**
 * @title TrailsCCTPV2Validator
 * @author Shun Kakinoki
 * @notice Library for validating Trails CCTP V2 data.
 */
library TrailsCCTPV2Validator {
    error MismatchedAttestationLength();
    error InvalidAttestation();

    bytes4 private constant DEPOSIT_FOR_BURN_WITH_HOOK_SELECTOR = ITokenMessengerV2.depositForBurnWithHook.selector;

    /**
     * @notice Validates that each attested CCTPExecutionInfo struct matches the corresponding inferred CCTPExecutionInfo struct.
     * @param inferredExecutionInfos Array of CCTPExecutionInfo structs inferred from current transaction data.
     * @param attestedExecutionInfos Array of CCTPExecutionInfo structs derived from attestations.
     */
    function validateExecutionInfos(
        CCTPExecutionInfo[] memory inferredExecutionInfos,
        CCTPExecutionInfo[] memory attestedExecutionInfos
    ) internal pure {
        if (inferredExecutionInfos.length != attestedExecutionInfos.length) {
            revert MismatchedAttestationLength();
        }

        for (uint256 i = 0; i < inferredExecutionInfos.length; i++) {
            if (keccak256(abi.encode(inferredExecutionInfos[i])) != keccak256(abi.encode(attestedExecutionInfos[i]))) {
                revert InvalidAttestation();
            }
        }
    }

    /**
     * @notice Validates the function selector of CCTP V2 calldata.
     * @dev It checks that the function selector matches `depositForBurnWithHook`.
     * @param data The raw calldata for the CCTP V2 operation.
     */
    function validate(bytes memory data) internal pure {
        require(bytes4(data) == DEPOSIT_FOR_BURN_WITH_HOOK_SELECTOR, "Invalid CCTP calldata");
    }
}
