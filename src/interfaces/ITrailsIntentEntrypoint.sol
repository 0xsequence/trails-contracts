// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ITrailsIntentEntrypoint
/// @notice Interface for the TrailsIntentEntrypoint contract
interface ITrailsIntentEntrypoint {
    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a user deposits tokens to an intent address
    /// @param user The user making the deposit
    /// @param intentAddress The intent address receiving the deposit
    /// @param amount The amount of tokens deposited
    event IntentDeposit(address indexed user, address indexed intentAddress, uint256 amount);

    /// @notice Emitted when a fee is paid.
    /// @param user The account from which the fee was taken.
    /// @param feeToken The ERC-20 token used to pay the fee.
    /// @param feeAmount The amount of the fee paid.
    /// @param feeCollector The address receiving the fee.
    event FeePaid(address indexed user, address indexed feeToken, uint256 feeAmount, address indexed feeCollector);

    // -------------------------------------------------------------------------
    // Views
    // -------------------------------------------------------------------------

    /// @notice Returns the EIP-712 domain separator used for intent signatures.
    /// forge-lint: disable-next-line(mixed-case-function)
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice Returns the trails intent typehash constant used in EIP-712 signatures.
    /// forge-lint: disable-next-line(mixed-case-function)
    function TRAILS_INTENT_TYPEHASH() external view returns (bytes32);

    /// @notice Returns the version string of the contract.
    /// forge-lint: disable-next-line(mixed-case-function)
    function VERSION() external view returns (string memory);

    /// @notice Returns whether an intent digest has already been consumed.
    /// @param digest The EIP-712 digest of the intent message.
    function usedIntents(bytes32 digest) external view returns (bool);

    /// @notice Returns the current nonce for a given user.
    /// @param user The user address to query.
    function nonces(address user) external view returns (uint256);

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /// @notice Deposit tokens to an intent address using ERC20 permit
    /// @param user The user making the deposit
    /// @param token The token to deposit (also used for fee payment)
    /// @param amount The amount to deposit
    /// @param permitAmount The amount to permit for spending (amount + feeAmount if paying fee)
    /// @param intentAddress The intent address to deposit to
    /// @param deadline The permit deadline
    /// @param nonce The nonce for this user
    /// @param feeAmount The amount of fee to pay (0 for no fee, paid in same token)
    /// @param feeCollector The address to receive the fee (address(0) for no fee)
    /// @param permitV The permit signature v component
    /// @param permitR The permit signature r component
    /// @param permitS The permit signature s component
    /// @param sigV The intent signature v component
    /// @param sigR The intent signature r component
    /// @param sigS The intent signature s component
    function depositToIntentWithPermit(
        address user,
        address token,
        uint256 amount,
        uint256 permitAmount,
        address intentAddress,
        uint256 deadline,
        uint256 nonce,
        uint256 feeAmount,
        address feeCollector,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) external;

    /// @notice Deposit tokens to an intent address (requires prior approval)
    /// @param user The user making the deposit
    /// @param token The token to deposit (also used for fee payment)
    /// @param amount The amount to deposit
    /// @param intentAddress The intent address to deposit to
    /// @param deadline The intent deadline
    /// @param nonce The nonce for this user
    /// @param feeAmount The amount of fee to pay (0 for no fee, paid in same token)
    /// @param feeCollector The address to receive the fee (address(0) for no fee)
    /// @param sigV The intent signature v component
    /// @param sigR The intent signature r component
    /// @param sigS The intent signature s component
    function depositToIntent(
        address user,
        address token,
        uint256 amount,
        address intentAddress,
        uint256 deadline,
        uint256 nonce,
        uint256 feeAmount,
        address feeCollector,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) external;
}
