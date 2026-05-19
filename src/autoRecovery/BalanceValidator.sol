// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title BalanceValidator
/// @notice Asserts the caller has zero native or ERC20 balance.
contract BalanceValidator {
  /// @notice The `owner` has a non-zero balance.
  error NonZeroBalance(address owner);
  /// @notice The `owner` has a non-zero balance of `token`.
  error NonZeroERC20Balance(address token, address owner);

  /// @notice Reverts if the caller has a non-zero native balance.
  function requireZeroBalance() external view {
    address owner = msg.sender;
    if (owner.balance > 0) {
      revert NonZeroBalance(owner);
    }
  }

  /// @notice Reverts if the caller has a non-zero balance of `token`.
  function requireZeroERC20Balance(address token) external view {
    address owner = msg.sender;
    if (IERC20(token).balanceOf(owner) > 0) {
      revert NonZeroERC20Balance(token, owner);
    }
  }
}
