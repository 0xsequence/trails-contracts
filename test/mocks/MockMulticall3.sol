// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";

contract MockMulticall3 {
    function aggregate3(IMulticall3.Call3[] calldata calls)
        external
        payable
        returns (IMulticall3.Result[] memory returnResults)
    {
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
}
