// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Guest} from "wallet-contracts-v3/Guest.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {CalldataDecode} from "src/utils/CalldataDecode.sol";
import {ReplaceBytes} from "src/utils/ReplaceBytes.sol";
import {LibBytes} from "wallet-contracts-v3/utils/LibBytes.sol";

/**
 * @title SharedProxy
 * @notice
 * A minimal execution proxy that "hydrates" a batch payload at execution time and then dispatches it
 * through the `Guest` module.
 * @dev
 * This is designed for intent flows where:
 * - The call bundle must be created/quoted off-chain.
 * - Some values (balances, runtime addresses, etc.) are only known at execution time.
 *
 * The contract is intentionally generic: it contains no business logic beyond:
 * 1) Decode `packedPayload` into `Payload.Decoded`.
 * 2) Apply a set of "hydrate commands" to mutate each call's `to`/`value`/`data`.
 * 3) Execute the resulting batch via `_dispatchGuest`.
 *
 * NOTE: This contract can temporarily hold funds during execution (e.g. as part of swaps) and can
 * optionally sweep them out via {hydrateExecuteAndSweep}.
 */
contract SharedProxy is Guest {
  using SafeERC20 for IERC20;
  using LibBytes for bytes;
  using ReplaceBytes for bytes;
  using CalldataDecode for bytes;

  // Custom errors keep failures cheap and make revert reasons machine-readable.
  error ArrayLengthMismatch();
  error ExecutionFailed(uint256 index, bytes result);
  error BalanceSweepFailed();
  error UnknownHydrateDataCommand(uint256 flag);

  // Hydration flags for mutating call `data` in-place.
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

  // Hydration flags for mutating a call's recipient (`to`).
  uint8 private constant HYDRATE_TO_MESSAGE_SENDER_ADDRESS = 0x0B;
  uint8 private constant HYDRATE_TO_TRANSACTION_ORIGIN_ADDRESS = 0x0C;

  // Hydration flags for mutating a call's ETH value (`value`).
  uint8 private constant HYDRATE_AMOUNT_SELF_BALANCE = 0x0D;

  /**
   * @notice Hydrates `packedPayload` using `hydratePayload` and then executes the batch.
   * @dev
   * `hydratePayload` is a byte stream of commands. Each command starts with a 1-byte `flag`.
   * The supported flags are the `HYDRATE_*` constants in this file.
   */
  function hydrateExecute(bytes calldata packedPayload, bytes calldata hydratePayload) external payable {
    _hydrateExecute(packedPayload, hydratePayload);
  }

  /**
   * @notice Hook used by Sequence wallets for delegatecall-based execution.
   * @dev Expects `data` to be ABI-encoded as `(bytes packedPayload, bytes hydratePayload)`.
   */
  function handleSequenceDelegateCall(bytes32, uint256, uint256, uint256, uint256, bytes calldata data)
    external
    virtual
  {
    (bytes calldata packedPayload, bytes calldata hydratePayload) = data.decodeBytesBytes();
    _hydrateExecute(packedPayload, hydratePayload);
  }

  /**
   * @notice Hydrates + executes, then sweeps ETH and a set of ERC20s to a recipient.
   * @param sweepTarget If zero address, defaults to `msg.sender`.
   * @param tokensToSweep Token list to sweep (each full balance of this contract).
   */
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
      // Guest handles execution dispatch for the decoded batch.
      Payload.Decoded memory decoded = Payload.fromPackedCalls(packedPayload);
      bytes32 opHash = Payload.hash(decoded);

      _hydrate(decoded, hydratePayload);
      _dispatchGuest(decoded, opHash);
    }
  }

  function _hydrate(Payload.Decoded memory decoded, bytes calldata hydratePayload) internal view {
    unchecked {
      // `hydratePayload` is parsed sequentially with `rindex` as the read cursor.
      //
      // Common fields:
      // - `tindex`: call index within `decoded.calls` (uint8).
      // - `cindex`: calldata byte offset within `decoded.calls[tindex].data` (uint16).
      //
      // For flags in [0x00..0x0A] we always read: `tindex` + `cindex`, followed by
      // flag-specific extra data.
      uint256 rindex;
      uint256 tindex;
      uint256 cindex;
      uint256 flag;

      while (rindex < hydratePayload.length) {
        (flag, rindex) = hydratePayload.readUint8(rindex);

        if (flag <= HYDRATE_DATA_ANY_ADDRESS_TOKEN_BALANCE) {
          // Data-hydration commands mutate `decoded.calls[tindex].data` in-place.
          (tindex, rindex) = hydratePayload.readUint8(rindex);
          (cindex, rindex) = hydratePayload.readUint16(rindex);

          if (flag == HYDRATE_DATA_SELF_ADDRESS) {
            // Insert `address(this)` at `cindex` as a raw 20-byte address.
            decoded.calls[tindex].data.replaceAddress(cindex, address(this));
          } else if (flag == HYDRATE_DATA_MESSAGE_SENDER_ADDRESS) {
            // Insert `msg.sender` at `cindex` as a raw 20-byte address.
            decoded.calls[tindex].data.replaceAddress(cindex, msg.sender);
          } else if (flag == HYDRATE_DATA_TRANSACTION_ORIGIN_ADDRESS) {
            // Insert `tx.origin` at `cindex` as a raw 20-byte address.
            decoded.calls[tindex].data.replaceAddress(cindex, tx.origin);
          } else if (flag == HYDRATE_DATA_SELF_BALANCE) {
            // Insert `address(this).balance` at `cindex` as a uint256.
            decoded.calls[tindex].data.replaceUint256(cindex, address(this).balance);
          } else if (flag == HYDRATE_DATA_MESSAGE_SENDER_BALANCE) {
            // Insert `msg.sender.balance` at `cindex` as a uint256.
            decoded.calls[tindex].data.replaceUint256(cindex, msg.sender.balance);
          } else if (flag == HYDRATE_DATA_TRANSACTION_ORIGIN_BALANCE) {
            // Insert `tx.origin.balance` at `cindex` as a uint256.
            decoded.calls[tindex].data.replaceUint256(cindex, tx.origin.balance);
          } else if (flag == HYDRATE_DATA_ANY_ADDRESS_BALANCE) {
            // Insert an arbitrary address's balance (address read from hydratePayload).
            address addr;
            (addr, rindex) = hydratePayload.readAddress(rindex);
            decoded.calls[tindex].data.replaceUint256(cindex, addr.balance);
          } else if (flag == HYDRATE_DATA_SELF_TOKEN_BALANCE) {
            // Insert this contract's ERC20 balance for a token read from hydratePayload.
            address token;
            (token, rindex) = hydratePayload.readAddress(rindex);
            decoded.calls[tindex].data.replaceUint256(cindex, IERC20(token).balanceOf(address(this)));
          } else if (flag == HYDRATE_DATA_MESSAGE_SENDER_TOKEN_BALANCE) {
            // Insert `msg.sender`'s ERC20 balance for a token read from hydratePayload.
            address token;
            (token, rindex) = hydratePayload.readAddress(rindex);
            decoded.calls[tindex].data.replaceUint256(cindex, IERC20(token).balanceOf(msg.sender));
          } else if (flag == HYDRATE_DATA_TRANSACTION_ORIGIN_TOKEN_BALANCE) {
            // Insert `tx.origin`'s ERC20 balance for a token read from hydratePayload.
            address token;
            (token, rindex) = hydratePayload.readAddress(rindex);
            decoded.calls[tindex].data.replaceUint256(cindex, IERC20(token).balanceOf(tx.origin));
          } else if (flag == HYDRATE_DATA_ANY_ADDRESS_TOKEN_BALANCE) {
            // Insert any address's ERC20 balance for:
            // - `token` read from hydratePayload
            // - `addr`  read from hydratePayload
            address token;
            address addr;
            (token, rindex) = hydratePayload.readAddress(rindex);
            (addr, rindex) = hydratePayload.readAddress(rindex);
            decoded.calls[tindex].data.replaceUint256(cindex, IERC20(token).balanceOf(addr));
          }
        } else if (flag == HYDRATE_TO_MESSAGE_SENDER_ADDRESS) {
          (tindex, rindex) = hydratePayload.readUint8(rindex);

          // Mutate the call recipient (`to`). The address is read from `hydratePayload`.
          (decoded.calls[tindex].to, rindex) = hydratePayload.readAddress(rindex);
        } else if (flag == HYDRATE_TO_TRANSACTION_ORIGIN_ADDRESS) {
          (tindex, rindex) = hydratePayload.readUint8(rindex);

          // Mutate the call recipient (`to`). The address is read from `hydratePayload`.
          (decoded.calls[tindex].to, rindex) = hydratePayload.readAddress(rindex);
        } else if (flag == HYDRATE_AMOUNT_SELF_BALANCE) {
          (tindex, rindex) = hydratePayload.readUint8(rindex);

          // Mutate the call value (`value`) to this contract's full ETH balance.
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
