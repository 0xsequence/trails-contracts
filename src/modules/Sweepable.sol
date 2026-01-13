// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Sweepable
/// @notice Contract for sweeping balances to a target address
contract Sweepable {
  using SafeERC20 for IERC20;

  /// @notice Error thrown when a native sweep fails
  error NativeSweepFailed();

  /// @notice Event emitted when a balance is swept
  event Sweep(address indexed token, address indexed recipient, uint256 amount);


  /// @notice Sweeps balances to a target address
  /// @param sweepTarget The address to sweep the balances to
  /// @param tokensToSweep The tokens to sweep
  /// @param sweepNative Whether to sweep native tokens
  function sweep(address sweepTarget, address[] calldata tokensToSweep, bool sweepNative) external {
    _sweep(sweepTarget, tokensToSweep, sweepNative);
  }

  function _sweep(address sweepTarget, address[] calldata tokensToSweep, bool sweepNative) internal {
    unchecked {
      // Either automatically sweep to the msg.sender, or to the specified address
      address sweepToAddress = sweepTarget == address(0) ? msg.sender : sweepTarget;

      // Sweep all token addresses specified
      for (uint256 i = 0; i < tokensToSweep.length; ++i) {
        uint256 balance = IERC20(tokensToSweep[i]).balanceOf(address(this));
        if (balance > 0) {
          IERC20(tokensToSweep[i]).safeTransfer(sweepToAddress, balance);
          emit Sweep(tokensToSweep[i], sweepToAddress, balance);
        }
      }

      // If we have balance, sweep it too
      if (sweepNative) {
        uint256 balance = address(this).balance;
        if (balance > 0) {
          (bool success,) = sweepToAddress.call{value: balance}("");
          if (!success) {
            revert NativeSweepFailed();
          }
          emit Sweep(address(0), sweepToAddress, balance);
        }
      }
    }
  }

  receive() external payable {}
}
