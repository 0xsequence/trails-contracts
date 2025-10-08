// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ITrailsIntentEntrypoint
/// @notice Interface for the Trails intent entrypoint contract handling signed deposits.
interface ITrailsIntentEntrypoint {
    /// @notice Emitted when an intent deposit is executed.
    /// @param user The signer authorizing the deposit.
    /// @param intentAddress The destination account receiving funds.
    /// @param amount The amount of tokens transferred.
    event IntentDeposit(address indexed user, address indexed intentAddress, uint256 amount);

    /// @notice Returns the EIP-712 domain separator used for intent signatures.
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice Returns whether an intent digest has already been consumed.
    /// @param digest The EIP-712 digest of the intent message.
    function usedIntents(bytes32 digest) external view returns (bool);

    /// @notice Executes an off-chain signed intent and pays using ERC-20 permit for allowance.
    /// @param user The signer authorizing the intent.
    /// @param token The ERC-20 token being transferred.
    /// @param amount The token amount to transfer.
    /// @param permitAmount The maximum allowance to grant via permit.
    /// @param intentAddress The recipient of the funds.
    /// @param deadline The signature expiration timestamp.
    /// @param permitV The permit signature recovery id.
    /// @param permitR The permit signature R value.
    /// @param permitS The permit signature S value.
    /// @param sigV The intent signature recovery id.
    /// @param sigR The intent signature R value.
    /// @param sigS The intent signature S value.
    function depositToIntentWithPermit(
        address user,
        address token,
        uint256 amount,
        uint256 permitAmount,
        address intentAddress,
        uint256 deadline,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) external;

    /// @notice Executes an off-chain signed intent using pre-approved ERC-20 allowance.
    /// @param user The signer authorizing the intent.
    /// @param token The ERC-20 token being transferred.
    /// @param amount The token amount to transfer.
    /// @param intentAddress The recipient of the funds.
    /// @param deadline The signature expiration timestamp.
    /// @param sigV The intent signature recovery id.
    /// @param sigR The intent signature R value.
    /// @param sigS The intent signature S value.
    function depositToIntent(
        address user,
        address token,
        uint256 amount,
        address intentAddress,
        uint256 deadline,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) external;
}
