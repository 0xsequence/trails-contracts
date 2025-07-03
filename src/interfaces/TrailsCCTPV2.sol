// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title ITokenMessengerV2
 * @notice Interface for the CCTP TokenMessengerV2 contract.
 * @dev See https://github.com/circlefin/evm-cctp-contracts for more details.
 */
interface ITokenMessengerV2 {
    /**
     * @notice Burns a token and initiates a cross-chain transfer.
     * @param amount The amount of the token to burn.
     * @param destinationDomain The domain of the destination chain.
     * @param mintRecipient The address of the recipient on the destination chain.
     * @param burnToken The address of the token to burn.
     * @param destinationCaller The address authorized to call `receiveMessage` on the destination.
     * @param hook The address of a contract to call with the message details.
     * @param maxFee The maximum fee to be paid for the cross-chain transfer.
     * @param minFinalityThreshold The minimum finality required for the message.
     * @return nonce The nonce of the message.
     */
    function depositForBurnWithHook(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        address hook,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external returns (uint64 nonce);
}

/**
 * @notice Represents the parameters for a CCTP execution.
 */
struct CCTPExecutionInfo {
    uint256 amount;
    uint32 destinationDomain;
    bytes32 mintRecipient;
    address burnToken;
    bytes32 destinationCaller;
    address hook;
    uint256 maxFee;
    uint32 minFinalityThreshold;
}
