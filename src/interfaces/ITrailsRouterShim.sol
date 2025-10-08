// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @title ITrailsRouterShim
/// @notice Interface for the router shim that bridges Sequence wallets to the Trails router.
interface ITrailsRouterShim {
    function ROUTER() external view returns (address);

    function handleSequenceDelegateCall(
        bytes32 opHash,
        uint256 startingGas,
        uint256 index,
        uint256 numCalls,
        uint256 space,
        bytes calldata data
    ) external;
}
