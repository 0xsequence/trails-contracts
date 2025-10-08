// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// -----------------------------------------------------------------------------
// Interfaces
// -----------------------------------------------------------------------------

interface IMulticall3 {
    struct Call3 {
        address target;
        bool allowFailure;
        bytes callData;
    }

    struct Result {
        bool success;
        bytes returnData;
    }

    function aggregate3(Call3[] calldata calls) external payable returns (Result[] memory returnData);
}
