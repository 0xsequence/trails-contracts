// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {LibOptim} from "wallet-contracts-v3/utils/LibOptim.sol";

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @title DepositAndCall
/// @notice Helper contract for depositing and calling a contract
/// @author Michael Standen
contract DepositAndCall {

    /// @notice Error thrown when the call fails
    error CallFailed();

    /// @notice The WETH contract
    IWETH public weth;

    /// @notice Constructor
    /// @param wethAddress The address of the WETH contract
    constructor(address wethAddress) {
        weth = IWETH(wethAddress);
    }

    /// @notice Deposits and calls a contract
    /// @param to The address of the contract to call
    /// @param data The data to call the contract with
    /// @return returnData The return data from the call
    function depositAndCall(address to, bytes calldata data) external payable returns (bytes memory) {
        uint256 amount = msg.value;
        weth.deposit{value: amount}();
        weth.approve(to, amount);
        bytes memory callData = data;
        bool success = LibOptim.call(to, 0, gasleft(), callData);
        if (!success) revert CallFailed();
        return LibOptim.returnData();
    }
}