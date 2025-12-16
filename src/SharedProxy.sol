pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Guest} from "wallet-contracts-v3/Guest.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

/**
 * @title Shared Proxy
 *
 * @notice
 * This contract provides a shared proxy that can be used by any intent address.
 * It is designed for scenarios where external contracts require off-chain quotes
 * and also need the `msg.sender` to be predetermined.
 *
 * @dev
 * - Not intended to hold funds.
 * - Does not implement any business logic.
 * - Enables interaction with external contracts under the constraints described.
 */
contract SharedProxy is Guest {
  using SafeERC20 for IERC20;

  error ArrayLengthMismatch();
  error ExecutionFailed(uint256 index, bytes result);
  error BalanceSweepFailed();

  function execute(bytes calldata packedPayload, address sweepTarget, address[] calldata tokensToSweep)
    external
    payable
  {
    // Guest module handles the batch of execution
    Payload.Decoded memory decoded = Payload.fromPackedCalls(packedPayload);
    bytes32 opHash = Payload.hash(decoded);
    _dispatchGuest(decoded, opHash);

    // Custom logic to sweep after the execution
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
}
