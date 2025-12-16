// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Guest} from "wallet-contracts-v3/Guest.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

import {LibBytes} from "wallet-contracts-v3/utils/LibBytes.sol";

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
  using LibBytes for bytes;

  error ArrayLengthMismatch();
  error ExecutionFailed(uint256 index, bytes result);
  error BalanceSweepFailed();
  error UnknownHydrateDataCommand(uint256 flag);

  uint8 private constant HYDRATE_DATA_SELF_ADDRESS = 0x00;
  uint8 private constant HYDRATE_DATA_MESSAGE_SENDER_ADDRESS = 0x01;

  uint8 private constant HYDRATE_DATA_SELF_BALANCE = 0x02;
  uint8 private constant HYDRATE_DATA_MESSAGE_SENDER_BALANCE = 0x03;
  uint8 private constant HYDRATE_DATA_ANY_ADDRESS_BALANCE = 0x04;

  uint8 private constant HYDRATE_DATA_SELF_TOKEN_BALANCE = 0x05;
  uint8 private constant HYDRATE_DATA_MESSAGE_SENDER_TOKEN_BALANCE = 0x06;
  uint8 private constant HYDRATE_DATA_ANY_ADDRESS_TOKEN_BALANCE = 0x07;

  uint8 private constant HYDRATE_TO_MESSAGE_SENDER_ADDRESS = 0x08;

  function hydrateExecute(bytes calldata packedPayload, bytes calldata hydratePayload) external payable {
    _hydrateExecute(packedPayload, hydratePayload);
  }

  function hydrateExecuteAndSweep(
    bytes calldata packedPayload,
    address sweepTarget,
    address[] calldata tokensToSweep,
    bytes calldata hydratePayload
  ) external payable {
    _hydrateExecute(packedPayload, hydratePayload);
    _sweep(sweepTarget, tokensToSweep);
  }

  function _hydrateExecute(bytes calldata packedPayload, bytes calldata hydratePayload) private {
    unchecked {
      // Guest module handles the batch of execution
      Payload.Decoded memory decoded = Payload.fromPackedCalls(packedPayload);
      bytes32 opHash = Payload.hash(decoded);

      // Dynamically hydrate the payload with information only known at execution time
      uint256 rindex;
      uint256 tindex;
      uint256 cindex;
      uint256 flag;

      while (rindex < hydratePayload.length) {
        (flag, rindex) = hydratePayload.readUint8(rindex);

        if (flag <= HYDRATE_DATA_ANY_ADDRESS_TOKEN_BALANCE) {
          // All hydrate data commands have a 1 byte transaction call index and a 2 byte
          // calldata offset. The size is always determined by the kind of command.
          (tindex, rindex) = hydratePayload.readUint8(rindex);
          (cindex, rindex) = hydratePayload.readUint16(rindex);

          if (flag == HYDRATE_DATA_SELF_ADDRESS) {
            // decoded.calls[tindex].data
          } else if (flag == HYDRATE_DATA_MESSAGE_SENDER_ADDRESS) {
            // decoded.calls[tindex].
          } else if (flag == HYDRATE_DATA_SELF_BALANCE) {
            // decoded.calls[tindex].
          } else if (flag == HYDRATE_DATA_MESSAGE_SENDER_BALANCE) {
            // decoded.calls[tindex].
          } else if (flag == HYDRATE_DATA_SELF_TOKEN_BALANCE) {
            // decoded.calls[tindex].
          }
        } else if (flag == HYDRATE_TO_MESSAGE_SENDER_ADDRESS) {
          (tindex, rindex) = hydratePayload.readUint8(rindex);

          // The message sender address is the address that sent the message to the contract.
          (decoded.calls[tindex].to, rindex) = hydratePayload.readAddress(rindex);
        } else {
          revert UnknownHydrateDataCommand(flag);
        }
      }

      _dispatchGuest(decoded, opHash);
    }
  }

  function _hydrate(Payload.Decoded memory decoded, bytes calldata hydratePayload) internal pure {

  }

  function _sweep(address sweepTarget, address[] calldata tokensToSweep) private {
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
