// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TrailsLiFiFlagDecoder} from "@/libraries/TrailsLiFiFlagDecoder.sol";
import {TrailsDecodingStrategy} from "@/interfaces/TrailsLiFi.sol";

/**
 * @title TrailsLiFiRouter
 * @author Shun Kakinoki
 * @notice A router contract that validates and executes LiFi calldata.
 */
contract TrailsLiFiRouter {
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
     * @dev This function first decodes the strategy and LiFi calldata from the input data,
     *      then uses TrailsLiFiFlagDecoder to validate it. If valid, it executes the
     *      LiFi calldata using delegatecall to the LiFi Diamond contract.
     * @param data The abi-encoded tuple of (TrailsDecodingStrategy, bytes) for the LiFi operation.
     */
    function execute(bytes calldata data) external payable {
        (TrailsDecodingStrategy strategy, bytes memory liFiData) = abi.decode(data, (TrailsDecodingStrategy, bytes));

        // This function will revert if the data is invalid
        TrailsLiFiFlagDecoder.decodeLiFiDataOrRevert(liFiData, strategy);

        (bool success,) = LIFI_DIAMOND.delegatecall(liFiData);
        if (!success) {
            revert ExecutionFailed();
        }
    }
}
