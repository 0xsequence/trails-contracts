// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {TrailsRelayValidator} from "@/libraries/TrailsRelayValidator.sol";
import {TrailsRelayConstants} from "@/libraries/TrailsRelayConstants.sol";

/**
 * @title TrailsRelayRouter
 * @author Shun Kakinoki
 * @notice A router contract that validates and executes Relay calldata.
 */
contract TrailsRelayRouter {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------

    using TrailsRelayValidator for bytes;

    // -------------------------------------------------------------------------
    // Immutable
    // -------------------------------------------------------------------------

    address public immutable RELAY_MULTICALL_PROXY;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error ExecutionFailed();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address relayMulticallProxy) {
        RELAY_MULTICALL_PROXY = relayMulticallProxy;
    }

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Validates and executes a Relay multicall operation via delegatecall.
     * @dev It first decodes the `Payload.Call` array from the input data, validates it
     *      using TrailsRelayValidator, and then executes the original calldata via
     *      delegatecall to the RELAY_MULTICALL_PROXY. Reverts if validation or execution fails.
     * @param data The abi-encoded array of Payload.Call structs for the Relay multicall.
     */
    function execute(bytes calldata data) external payable {
        data.validate();

        // Execute the original calldata
        (bool success,) = RELAY_MULTICALL_PROXY.delegatecall(data);
        if (!success) {
            revert ExecutionFailed();
        }
    }
}
