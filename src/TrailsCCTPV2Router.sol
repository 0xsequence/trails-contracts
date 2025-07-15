// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ITokenMessengerV2} from "@/interfaces/TrailsCCTPV2.sol";

/**
 * @title TrailsCCTPV2Router
 * @author Shun Kakinoki
 * @notice A router contract that validates and executes CCTP V2 calldata.
 */
contract TrailsCCTPV2Router {
    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    // From: https://developers.circle.com/stablecoins/evm-smart-contracts
    address public constant TOKEN_MESSENGER = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;

    bytes4 private constant DEPOSIT_FOR_BURN_WITH_HOOK_SELECTOR = ITokenMessengerV2.depositForBurnWithHook.selector;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error ExecutionFailed();

    /**
     * @notice Validates and executes a CCTP V2 `depositForBurnWithHook` call via delegatecall.
     * @dev It checks that the function selector matches, then executes the calldata via
     *      delegatecall to the CCTP Token Messenger contract.
     *      Reverts if the selector is mismatched or execution fails.
     * @param data The raw calldata for the CCTP V2 operation.
     */
    function execute(bytes calldata data) external payable {
        require(bytes4(data) == DEPOSIT_FOR_BURN_WITH_HOOK_SELECTOR, "Invalid CCTP calldata");

        (bool success,) = TOKEN_MESSENGER.delegatecall(data);
        if (!success) {
            revert ExecutionFailed();
        }
    }
}
