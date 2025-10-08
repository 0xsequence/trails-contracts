// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IMulticall3} from "./IMulticall3.sol";

/// @title ITrailsRouter
/// @notice Interface describing the delegate-call router utilities exposed to Sequence wallets.
interface ITrailsRouter {
    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event BalanceInjectorCall(
        address indexed token,
        address indexed target,
        bytes32 placeholder,
        uint256 amountReplaced,
        uint256 amountOffset,
        bool success,
        bytes result
    );
    event Refund(address indexed token, address indexed recipient, uint256 amount);
    event Sweep(address indexed token, address indexed recipient, uint256 amount);
    event RefundAndSweep(
        address indexed token,
        address indexed refundRecipient,
        uint256 refundAmount,
        address indexed sweepRecipient,
        uint256 actualRefund,
        uint256 remaining
    );
    event ActualRefund(address indexed token, address indexed recipient, uint256 expected, uint256 actual);

    // ---------------------------------------------------------------------
    // Multicall Operations
    // ---------------------------------------------------------------------

    function execute(bytes calldata data) external payable returns (IMulticall3.Result[] memory returnResults);

    function pullAndExecute(address token, bytes calldata data)
        external
        payable
        returns (IMulticall3.Result[] memory returnResults);

    function pullAmountAndExecute(address token, uint256 amount, bytes calldata data)
        external
        payable
        returns (IMulticall3.Result[] memory returnResults);

    // ---------------------------------------------------------------------
    // Balance Injection
    // ---------------------------------------------------------------------

    function injectSweepAndCall(
        address token,
        address target,
        bytes calldata callData,
        uint256 amountOffset,
        bytes32 placeholder
    ) external payable;

    function injectAndCall(
        address token,
        address target,
        bytes calldata callData,
        uint256 amountOffset,
        bytes32 placeholder
    ) external payable;

    function validateOpHashAndSweep(bytes32 opHash, address token, address recipient) external payable;

    // ---------------------------------------------------------------------
    // Sweeper
    // ---------------------------------------------------------------------

    function sweep(address token, address recipient) external payable;

    function refundAndSweep(address token, address refundRecipient, uint256 refundAmount, address sweepRecipient)
        external
        payable;

    // ---------------------------------------------------------------------
    // Delegate Entry
    // ---------------------------------------------------------------------

    function handleSequenceDelegateCall(
        bytes32 opHash,
        uint256 startingGas,
        uint256 index,
        uint256 numCalls,
        uint256 space,
        bytes calldata data
    ) external;

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function multicall3() external view returns (address);
}
