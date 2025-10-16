// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IMulticall3} from "src/interfaces/IMulticall3.sol";

// -----------------------------------------------------------------------------
// Mock Contract
// -----------------------------------------------------------------------------

contract MockMulticall3 {
    bool public shouldFail;

    function setShouldFail(bool _shouldFail) external {
        shouldFail = _shouldFail;
    }

    function aggregate3(IMulticall3.Call3[] calldata calls)
        external
        payable
        returns (IMulticall3.Result[] memory returnResults)
    {
        if (shouldFail) {
            revert("MockMulticall3: forced failure");
        }

        returnResults = new IMulticall3.Result[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            IMulticall3.Call3 calldata call = calls[i];
            (bool success, bytes memory returnData) = call.target.call(call.callData);
            returnResults[i] = IMulticall3.Result({success: success, returnData: returnData});
            if (!call.allowFailure && !success) {
                revert("Multicall3: call failed");
            }
        }
    }

    function aggregate3Value(IMulticall3.Call3Value[] calldata calls)
        external
        payable
        returns (IMulticall3.Result[] memory returnResults)
    {
        if (shouldFail) {
            revert("MockMulticall3: forced failure");
        }

        returnResults = new IMulticall3.Result[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            IMulticall3.Call3Value calldata call = calls[i];
            (bool success, bytes memory returnData) = call.target.call{value: call.value}(call.callData);
            returnResults[i] = IMulticall3.Result({success: success, returnData: returnData});
            if (!call.allowFailure && !success) {
                revert("Multicall3: call failed");
            }
        }
    }
}
