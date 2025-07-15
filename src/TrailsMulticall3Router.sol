// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";

/**
 * @title TrailsMulticall3Router
 * @author Sequence
 * @notice A wrapper to execute multiple calls via DELEGATECALL to preserve the original msg.sender.
 * @dev This contract mimics the Multicall3 interface but executes sub-calls via DELEGATECALL
 *      to ensure that for the sub-calls, msg.sender is the original caller of this contract.
 *      This is useful for smart contract wallets (intent addresses) that need to control msg.sender.
 */
contract TrailsMulticall3Router {
    /**
     * @notice Aggregates multiple calls in a single transaction.
     * @dev See the contract-level documentation for the logic on how the call is performed.
     * @param calls An array of call objects.
     * @return returnData An array of result objects from each call.
     */
    function aggregate3(IMulticall3.Call3[] calldata calls)
        public
        payable
        returns (IMulticall3.Result[] memory returnData)
    {
        returnData = new IMulticall3.Result[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory data) = calls[i].target.delegatecall(calls[i].callData);
            if (!calls[i].allowFailure) {
                require(success, "TrailsMulticall3Router: call failed");
            }
            returnData[i] = IMulticall3.Result(success, data);
        }
    }
} 
