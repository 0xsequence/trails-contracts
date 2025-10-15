// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IMulticall3
/// @notice Minimal subset of Multicall3 used by Trails router.
/// @dev Matches the canonical implementation deployed at `0xcA11bde05977b3631167028862bE2a173976CA11`.
interface IMulticall3 {
    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    struct Call3 {
        address target;
        bool allowFailure;
        bytes callData;
    }

    struct Call3Value {
        address target;
        bool allowFailure;
        uint256 value;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
    }

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    function aggregate3(Call3[] calldata calls) external payable returns (Result[] memory returnData);

    function aggregate3Value(Call3Value[] calldata calls) external payable returns (Result[] memory returnData);
}
