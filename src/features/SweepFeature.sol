// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibBytes} from "wallet-contracts-v3/utils/LibBytes.sol";

/// @title SweepFeature
/// @author Michael Standen
/// @notice A helper for sweeping all tokens owned by the address.
contract SweepFeature {
    using LibBytes for bytes;

    /// @notice Thrown when a native transfer fails.
    error NativeTransferFailed();

    /// @notice Emitted when a token is swept.
    /// @param token The address of the token swept.
    /// @param recipient The address to send the swept tokens to.
    /// @param amount The amount of tokens swept.
    event Sweep(address token, address recipient, uint256 amount);

    /// @notice Sweeps the entire balance to recipient.
    /// @dev Intended for use with Sequence's delegated extension module.
    /// @param data The data packed as (address token, address recipient, uint256 maxAmount).
    /// @dev The maxAmount is optional and will default to the entire balance if not provided.
    function handleSequenceDelegateCall(
        bytes32, // opHash (unused)
        uint256, // startingGas (unused)
        uint256, // index (unused)
        uint256, // numCalls (unused)
        uint256, // space (unused)
        bytes calldata data
    )
        external
    {
        uint256 pointer;
        address token;
        address recipient;
        uint256 maxAmount = type(uint256).max;
        (token, pointer) = data.readAddress(pointer);
        (recipient, pointer) = data.readAddress(pointer);
        if (pointer < data.length) {
            (maxAmount,) = data.readUint256(pointer);
        }
        _sweep(token, recipient, maxAmount);
    }

    /// @notice Sweeps the entire balance to recipient.
    /// @dev Intended for use with delegatecall.
    /// @param token The address of the token to sweep. Use address(0) for the native token.
    /// @param recipient The address to send the swept tokens to.
    function sweep(address token, address recipient) external {
        _sweep(token, recipient, type(uint256).max);
    }

    /// @notice Sweeps up to maxAmount to recipient.
    /// @dev Intended for use with delegatecall.
    /// @param token The address of the token to sweep. Use address(0) for the native token.
    /// @param recipient The address to send the swept tokens to.
    /// @param maxAmount The maximum amount to sweep.
    function sweep(address token, address recipient, uint256 maxAmount) external {
        _sweep(token, recipient, maxAmount);
    }

    function _sweep(address token, address recipient, uint256 maxAmount) internal {
        uint256 balance = token == address(0) ? address(this).balance : IERC20(token).balanceOf(address(this));
        uint256 amount = maxAmount > balance ? balance : maxAmount;
        if (token == address(0)) {
            (bool success,) = recipient.call{value: amount}("");
            if (!success) {
                revert NativeTransferFailed();
            }
        } else {
            SafeERC20.safeTransfer(IERC20(token), recipient, amount);
        }
        emit Sweep(token, recipient, amount);
    }
}
