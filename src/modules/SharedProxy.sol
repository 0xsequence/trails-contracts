// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Guest} from "wallet-contracts-v3/Guest.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {CalldataDecode} from "src/utils/CalldataDecode.sol";
import {ReplaceBytes} from "src/utils/ReplaceBytes.sol";
import {LibBytes} from "wallet-contracts-v3/utils/LibBytes.sol";
import {CalldataDecode} from "src/utils/CalldataDecode.sol";

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
  using ReplaceBytes for bytes;
  using CalldataDecode for bytes;

  error ArrayLengthMismatch();
  error ExecutionFailed(uint256 index, bytes result);
  error BalanceSweepFailed();
  error UnknownHydrateDataCommand(uint256 flag);

  uint8 private constant HYDRATE_DATA_SELF_ADDRESS = 0x00;
  uint8 private constant HYDRATE_DATA_MESSAGE_SENDER_ADDRESS = 0x01;
  uint8 private constant HYDRATE_DATA_TRANSACTION_ORIGIN_ADDRESS = 0x02;

  uint8 private constant HYDRATE_DATA_SELF_BALANCE = 0x03;
  uint8 private constant HYDRATE_DATA_MESSAGE_SENDER_BALANCE = 0x04;
  uint8 private constant HYDRATE_DATA_TRANSACTION_ORIGIN_BALANCE = 0x05;
  uint8 private constant HYDRATE_DATA_ANY_ADDRESS_BALANCE = 0x06;

  uint8 private constant HYDRATE_DATA_SELF_TOKEN_BALANCE = 0x07;
  uint8 private constant HYDRATE_DATA_MESSAGE_SENDER_TOKEN_BALANCE = 0x08;
  uint8 private constant HYDRATE_DATA_TRANSACTION_ORIGIN_TOKEN_BALANCE = 0x09;
  uint8 private constant HYDRATE_DATA_ANY_ADDRESS_TOKEN_BALANCE = 0x0A;

  uint8 private constant HYDRATE_TO_MESSAGE_SENDER_ADDRESS = 0x0B;
  uint8 private constant HYDRATE_TO_TRANSACTION_ORIGIN_ADDRESS = 0x0C;

  uint8 private constant HYDRATE_AMOUNT_SELF_BALANCE = 0x0D;

  // Useful in delegatecall contexts, since sweeping is not necessary
  // yet it allows to dynamically hydrate the payload with information that was not known at the creation of the intent.
  function hydrateExecute(bytes calldata packedPayload, bytes calldata hydratePayload) external payable {
    _hydrateExecute(packedPayload, hydratePayload);
  }

  function handleSequenceDelegateCall(bytes32, uint256, uint256, uint256, uint256, bytes calldata data)
    external
    virtual
  {
    (bytes calldata packedPayload, bytes calldata hydratePayload) = data.decodeBytesBytes();
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

  function _hydrateExecute(bytes calldata packedPayload, bytes calldata hydratePayload) internal {
    unchecked {
      // Guest module handles the batch of execution
      Payload.Decoded memory decoded = Payload.fromPackedCalls(packedPayload);
      bytes32 opHash = Payload.hash(decoded);

      _hydrate(decoded, hydratePayload);
      _dispatchGuest(decoded, opHash);
    }
  }

  function _hydrate(Payload.Decoded memory decoded, bytes calldata hydratePayload) internal view {
    unchecked {
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
            // Insert the contract's address at the specified offset
            decoded.calls[tindex].data.replaceAddress(cindex, address(this));
          } else if (flag == HYDRATE_DATA_MESSAGE_SENDER_ADDRESS) {
            // Insert the message sender's address at the specified offset
            decoded.calls[tindex].data.replaceAddress(cindex, msg.sender);
          } else if (flag == HYDRATE_DATA_TRANSACTION_ORIGIN_ADDRESS) {
            // Insert the transaction origin's address at the specified offset
            decoded.calls[tindex].data.replaceAddress(cindex, tx.origin);
          } else if (flag == HYDRATE_DATA_SELF_BALANCE) {
            // Insert the contract's balance at the specified offset
            decoded.calls[tindex].data.replaceUint256(cindex, address(this).balance);
          } else if (flag == HYDRATE_DATA_MESSAGE_SENDER_BALANCE) {
            // Insert the message sender's balance at the specified offset
            decoded.calls[tindex].data.replaceUint256(cindex, msg.sender.balance);
          } else if (flag == HYDRATE_DATA_TRANSACTION_ORIGIN_BALANCE) {
            // Insert the transaction origin's balance at the specified offset
            decoded.calls[tindex].data.replaceUint256(cindex, tx.origin.balance);
          } else if (flag == HYDRATE_DATA_ANY_ADDRESS_BALANCE) {
            // Insert any address's balance at the specified offset
            address addr;
            (addr, rindex) = hydratePayload.readAddress(rindex);
            uint256 bal = addr.balance;
            decoded.calls[tindex].data.replaceUint256(cindex, bal);
          } else if (flag == HYDRATE_DATA_SELF_TOKEN_BALANCE) {
            // Insert this contract's ERC20 balance for the token address specified (extracted from calldata)
            // Assume next 20 bytes in hydratePayload is the token address
            address token;
            (token, rindex) = hydratePayload.readAddress(rindex);
            uint256 bal = IERC20(token).balanceOf(address(this));
            decoded.calls[tindex].data.replaceUint256(cindex, bal);
          } else if (flag == HYDRATE_DATA_MESSAGE_SENDER_TOKEN_BALANCE) {
            // Insert the message sender's ERC20 balance for the token address specified (extracted from calldata)
            // Assume next 20 bytes in hydratePayload is the token address
            address token;
            (token, rindex) = hydratePayload.readAddress(rindex);
            uint256 bal = IERC20(token).balanceOf(msg.sender);
            decoded.calls[tindex].data.replaceUint256(cindex, bal);
          } else if (flag == HYDRATE_DATA_TRANSACTION_ORIGIN_TOKEN_BALANCE) {
            // Insert the transaction origin's ERC20 balance for the token address specified (extracted from calldata)
            // Assume next 20 bytes in hydratePayload is the token address
            address token;
            (token, rindex) = hydratePayload.readAddress(rindex);
            uint256 bal = IERC20(token).balanceOf(tx.origin);
            decoded.calls[tindex].data.replaceUint256(cindex, bal);
          } else if (flag == HYDRATE_DATA_ANY_ADDRESS_TOKEN_BALANCE) {
            // Insert any address's ERC20 balance for the token address specified (extracted from calldata)
            // Assume next 20 bytes in hydratePayload is the token address
            // and the next 20 bytes is the address to get the balance of
            address token;
            address addr;
            (token, rindex) = hydratePayload.readAddress(rindex);
            (addr, rindex) = hydratePayload.readAddress(rindex);
            uint256 bal = IERC20(token).balanceOf(addr);
            decoded.calls[tindex].data.replaceUint256(cindex, bal);
          }
        } else if (flag == HYDRATE_TO_MESSAGE_SENDER_ADDRESS) {
          (tindex, rindex) = hydratePayload.readUint8(rindex);

          // The message sender address is the address that sent the message to the contract.
          (decoded.calls[tindex].to, rindex) = hydratePayload.readAddress(rindex);
        } else if (flag == HYDRATE_TO_TRANSACTION_ORIGIN_ADDRESS) {
          (tindex, rindex) = hydratePayload.readUint8(rindex);

          // The transaction origin address is the address that originated the transaction.
          (decoded.calls[tindex].to, rindex) = hydratePayload.readAddress(rindex);
        } else if (flag == HYDRATE_AMOUNT_SELF_BALANCE) {
          (tindex, rindex) = hydratePayload.readUint8(rindex);

          // The amount is the balance of the contract.
          decoded.calls[tindex].value = address(this).balance;
        } else {
          revert UnknownHydrateDataCommand(flag);
        }
      }
    }
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
