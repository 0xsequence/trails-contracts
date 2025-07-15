// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TrailsLiFiValidator} from "@/libraries/TrailsLiFiValidator.sol";
import {TrailsDecodingStrategy} from "@/interfaces/TrailsLiFi.sol";

/**
 * @title TrailsLiFiRouter
 * @author Shun Kakinoki
 * @notice A router contract that validates and executes LiFi calldata.
 */
contract TrailsLiFiRouter {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------

    using TrailsLiFiValidator for bytes;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    address public immutable LIFI_DIAMOND;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error ExecutionFailed();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address _lifiDiamond) {
        require(_lifiDiamond != address(0), "Invalid LiFi Diamond address");
        LIFI_DIAMOND = _lifiDiamond;
    }

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /**
     * @notice Validates and executes a LiFi operation via delegatecall.
     * @dev This function first validates the input data, then decodes it to extract the
     *      LiFi calldata, and executes it using delegatecall to the LiFi Diamond contract.
     * @param data The abi-encoded tuple of (TrailsDecodingStrategy, bytes) for the LiFi operation.
     */
    function execute(bytes calldata data) external payable {
        data.validate();

        (, bytes memory liFiData) = abi.decode(data, (TrailsDecodingStrategy, bytes));

        (bool success,) = LIFI_DIAMOND.delegatecall(liFiData);
        if (!success) {
            revert ExecutionFailed();
        }
    }
}
