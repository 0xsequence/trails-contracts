// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {CCTPExecutionInfo, ITokenMessengerV2} from "../interfaces/TrailsCCTPV2.sol";

/**
 * @title TrailsCCTPV2Decoder
 * @author Shun Kakinoki
 * @notice Library to decode calldata for Trails CCTP V2 operations.
 */
library TrailsCCTPV2Decoder {
    error InvalidCalldata();

    bytes4 private constant DEPOSIT_FOR_BURN_WITH_HOOK_SELECTOR =
        ITokenMessengerV2.depositForBurnWithHook.selector;

    /**
     * @notice Decodes the calldata of a `depositForBurnWithHook` call.
     * @param _callData The calldata of the transaction.
     * @return _executionInfo The decoded CCTP execution info.
     */
    function decodeCCTPData(bytes memory _callData)
        internal
        pure
        returns (CCTPExecutionInfo memory _executionInfo)
    {
        if (bytes4(_callData) != DEPOSIT_FOR_BURN_WITH_HOOK_SELECTOR) {
            revert InvalidCalldata();
        }

        bytes memory params = new bytes(_callData.length - 4);
        for (uint i = 0; i < params.length; i++) {
            params[i] = _callData[i + 4];
        }

        (
            uint256 amount,
            uint32 destinationDomain,
            bytes32 mintRecipient,
            address burnToken,
            bytes32 destinationCaller,
            address hook,
            uint256 maxFee,
            uint32 minFinalityThreshold
        ) = abi.decode(params, (uint256, uint32, bytes32, address, bytes32, address, uint256, uint32));
        _executionInfo = CCTPExecutionInfo({
            amount: amount,
            destinationDomain: destinationDomain,
            mintRecipient: mintRecipient,
            burnToken: burnToken,
            destinationCaller: destinationCaller,
            hook: hook,
            maxFee: maxFee,
            minFinalityThreshold: minFinalityThreshold
        });
    }
} 