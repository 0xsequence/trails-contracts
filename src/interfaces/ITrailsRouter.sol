// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDelegatedExtension} from "wallet-contracts-v3/modules/interfaces/IDelegatedExtension.sol";

/// @title ITrailsRouter
/// @notice Interface describing the delegate-call router utilities exposed to Sequence wallets.
interface ITrailsRouter is IDelegatedExtension {
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
    // Router Operations
    // ---------------------------------------------------------------------

    /// @notice Executes Sequence V3 CallsPayload format batch calls.
    /// @dev Forwards CallsPayload to Guest module for execution. Guest module doesn't return results.
    /// @param data The Sequence V3 CallsPayload encoded data to execute.
    function execute(bytes calldata data) external payable;

    /// @notice Pull tokens from msg.sender, then execute batch calls.
    /// @dev For ERC20: pulls entire balance and requires prior approval. For ETH: uses msg.value.
    /// @param token The ERC20 token to pull, or address(0) for ETH.
    /// @param data The Sequence V3 CallsPayload encoded data to execute.
    function pullAndExecute(address token, bytes calldata data) external payable;

    /// @notice Pull specific amount of tokens from msg.sender, then execute batch calls.
    /// @dev For ERC20: requires prior approval. For ETH: requires msg.value.
    /// @param token The ERC20 token to pull, or address(0) for ETH.
    /// @param amount The amount to pull.
    /// @param data The Sequence V3 CallsPayload encoded data to execute.
    function pullAmountAndExecute(address token, uint256 amount, bytes calldata data) external payable;

    // ---------------------------------------------------------------------
    // Balance Injection
    // ---------------------------------------------------------------------

    /// @notice Sweeps tokens from msg.sender and calls target with modified calldata.
    /// @dev Transfers tokens from msg.sender to this contract first.
    /// @param token The ERC-20 token to sweep, or address(0) for ETH.
    /// @param target The address to call with modified calldata.
    /// @param callData The original calldata (must include a 32-byte placeholder).
    /// @param amountOffset The byte offset in calldata where the placeholder is located.
    /// @param placeholder The 32-byte placeholder that will be replaced with balance.
    function injectSweepAndCall(
        address token,
        address target,
        bytes calldata callData,
        uint256 amountOffset,
        bytes32 placeholder
    ) external payable;

    /// @notice Injects balance and calls target (for delegatecall context).
    /// @param token The ERC-20 token to sweep, or address(0) for ETH.
    /// @param target The address to call with modified calldata.
    /// @param callData The original calldata (must include a 32-byte placeholder).
    /// @param amountOffset The byte offset in calldata where the placeholder is located.
    /// @param placeholder The 32-byte placeholder that will be replaced with balance.
    function injectAndCall(
        address token,
        address target,
        bytes calldata callData,
        uint256 amountOffset,
        bytes32 placeholder
    ) external payable;

    /// @notice Validates that the success sentinel for an opHash is set, then sweeps tokens.
    /// @dev For delegatecall context. Used to ensure prior operation succeeded.
    /// @param opHash The operation hash to validate.
    /// @param token The token to sweep.
    /// @param recipient The recipient of the sweep.
    function validateOpHashAndSweep(bytes32 opHash, address token, address recipient) external payable;

    // ---------------------------------------------------------------------
    // Sweeper
    // ---------------------------------------------------------------------

    /// @notice Sweeps the entire balance to recipient.
    /// @dev For delegatecall context. Transfers all tokens/ETH held by the wallet to the recipient.
    /// @param token The address of the token to sweep. Use address(0) for the native token.
    /// @param recipient The address to send the swept tokens to.
    function sweep(address token, address recipient) external payable;

    /// @notice Refunds up to `_refundAmount` to `_refundRecipient`, then sweeps any remaining balance to `_sweepRecipient`.
    /// @dev For delegatecall context.
    /// @param token The token address to operate on. Use address(0) for native.
    /// @param refundRecipient Address receiving the refund portion.
    /// @param refundAmount Maximum amount to refund.
    /// @param sweepRecipient Address receiving the remaining balance.
    function refundAndSweep(address token, address refundRecipient, uint256 refundAmount, address sweepRecipient)
        external
        payable;

    // ---------------------------------------------------------------------
    // Delegate Entry
    // ---------------------------------------------------------------------

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
