// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDelegatedExtension} from "wallet-contracts-v3/modules/interfaces/IDelegatedExtension.sol";

/// @title ITrailsRouterShim
/// @notice Interface for the router shim that bridges Sequence wallets to the Trails router.
interface ITrailsRouterShim is IDelegatedExtension {
    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /// @inheritdoc IDelegatedExtension
    function handleSequenceDelegateCall(
        bytes32 opHash,
        uint256 startingGas,
        uint256 index,
        uint256 numCalls,
        uint256 space,
        bytes calldata data
    ) external;
}
