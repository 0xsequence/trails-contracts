// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Sweep
/// @notice Contract for sweeping balances to a target address
contract Sweep {
  using SafeERC20 for IERC20;

  /// @notice Error thrown when a balance sweep fails
  error BalanceSweepFailed();

  /// @notice Sweeps balances to a target address
  /// @param sweepTarget The address to sweep the balances to
  /// @param tokensToSweep The tokens to sweep
  function sweep(address sweepTarget, address[] calldata tokensToSweep) external {
    _sweep(sweepTarget, tokensToSweep);
  }

  function _sweep(address sweepTarget, address[] calldata tokensToSweep) internal {
    unchecked {
      // Either automatically sweep to the msg.sender, or to the specified address
      address sweepToAddress = sweepTarget == address(0) ? msg.sender : sweepTarget;

      // Sweep all token addresses specified
      for (uint256 i = 0; i < tokensToSweep.length; ++i) {
        IERC20(tokensToSweep[i]).safeTransfer(sweepToAddress, IERC20(tokensToSweep[i]).balanceOf(address(this)));
      }

      // If we have balance, sweep it too
      if (address(this).balance > 0) {
        (bool success,) = sweepToAddress.call{value: address(this).balance}("");
        if (!success) {
          revert BalanceSweepFailed();
        }
      }
    }
  }

  receive() external payable {}
}
