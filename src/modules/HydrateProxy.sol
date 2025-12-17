// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {Sweep} from "src/modules/Sweep.sol";
import {CalldataDecode} from "src/utils/CalldataDecode.sol";
import {ReplaceBytes} from "src/utils/ReplaceBytes.sol";
import {LibBytes} from "wallet-contracts-v3/utils/LibBytes.sol";
import {Calls} from "wallet-contracts-v3/modules/Calls.sol";
import {LibOptim} from "wallet-contracts-v3/utils/LibOptim.sol";

/**
 * @title HydrateProxy
 * @notice
 * A minimal execution proxy that "hydrates" a batch payload at execution time and then executes it.
 * @dev
 * This is designed for intent flows where:
 * - The call bundle must be created/quoted off-chain.
 * - Some values (balances, runtime addresses, etc.) are only known at execution time.
 *
 * The contract is intentionally generic: it contains no business logic beyond:
 * 1) Decode `packedPayload` into `Payload.Decoded`.
 * 2) Apply a set of "hydrate commands" to mutate each call's `to`/`value`/`data`.
 * 3) Execute the resulting batch (sequential `call`s with `Payload.Call` semantics).
 *
 * NOTE: This contract can temporarily hold funds during execution (e.g. as part of swaps) and can
 * optionally sweep them out via {hydrateExecuteAndSweep}.
 */
contract HydrateProxy is Sweep {
  using LibBytes for bytes;
  using ReplaceBytes for bytes;
  using CalldataDecode for bytes;

  error UnknownHydrateDataCommand(uint256 flag);
  error DelegateCallNotAllowed(uint256 index);

  // Hydration stream delimiter: ends the current call's hydration section.
  uint256 private constant SIGNAL_NEXT_HYDRATE = 0x00;

  // Hydration flags for mutating the current call's `data` in-place.
  uint256 private constant HYDRATE_DATA_SELF_ADDRESS = 0x01;
  uint256 private constant HYDRATE_DATA_MESSAGE_SENDER_ADDRESS = 0x02;
  uint256 private constant HYDRATE_DATA_TRANSACTION_ORIGIN_ADDRESS = 0x03;

  uint256 private constant HYDRATE_DATA_SELF_BALANCE = 0x04;
  uint256 private constant HYDRATE_DATA_MESSAGE_SENDER_BALANCE = 0x05;
  uint256 private constant HYDRATE_DATA_TRANSACTION_ORIGIN_BALANCE = 0x06;
  uint256 private constant HYDRATE_DATA_ANY_ADDRESS_BALANCE = 0x07;

  uint256 private constant HYDRATE_DATA_SELF_TOKEN_BALANCE = 0x08;
  uint256 private constant HYDRATE_DATA_MESSAGE_SENDER_TOKEN_BALANCE = 0x09;
  uint256 private constant HYDRATE_DATA_TRANSACTION_ORIGIN_TOKEN_BALANCE = 0x0A;
  uint256 private constant HYDRATE_DATA_ANY_ADDRESS_TOKEN_BALANCE = 0x0B;

  // Hydration flags for mutating a call's recipient (`to`).
  uint256 private constant HYDRATE_TO_MESSAGE_SENDER_ADDRESS = 0x0C;
  uint256 private constant HYDRATE_TO_TRANSACTION_ORIGIN_ADDRESS = 0x0D;

  // Hydration flags for mutating a call's ETH value (`value`).
  uint256 private constant HYDRATE_AMOUNT_SELF_BALANCE = 0x0E;

  /**
   * @notice Hydrates `packedPayload` using `hydratePayload` and then executes the batch.
   * @dev
   * `hydratePayload` is a byte stream grouped by call index:
   * - Starts with a 1-byte `tindex` (the call to hydrate).
   * - Followed by commands for that call. Each command starts with a 1-byte `flag`.
   * - A `SIGNAL_NEXT_HYDRATE` (0x00) ends the current call's section; if more bytes remain, the next
   *   byte is the next `tindex`.
   *
   * The supported command flags are the `HYDRATE_*` constants in this file.
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
      // Decode + hash the payload, then apply hydration and execute each call sequentially.
      Payload.Decoded memory decoded = Payload.fromPackedCalls(packedPayload);
      bytes32 opHash = Payload.hash(decoded);
      bytes32 hydratableOpHash = LibOptim.fkeccak256(opHash, keccak256(hydratePayload));

      (uint256 rindex, uint256 tindex) = _firstHydrateCall(hydratePayload);
      bool errorFlag = false;

      uint256 numCalls = decoded.calls.length;
      for (uint256 i = 0; i < numCalls; i++) {
        if (tindex == i) {
          (rindex, tindex) = _hydrate(decoded, hydratePayload, rindex, tindex);
        }

        Payload.Call memory call = decoded.calls[i];

        // Skip `onlyFallback` calls unless the immediately preceding call failed and was ignored.
        if (call.onlyFallback && !errorFlag) {
          emit Calls.CallSkipped(hydratableOpHash, i);
          continue;
        }

        // `onlyFallback` only inspects the immediately preceding call.
        errorFlag = false;

        uint256 gasLimit = call.gasLimit;
        if (gasLimit != 0 && gasleft() < gasLimit) {
          revert Calls.NotEnoughGas(decoded, i, gasleft());
        }

        if (call.delegateCall) {
          // This proxy supports only `call` (not `delegatecall`) for payload execution.
          revert DelegateCallNotAllowed(i);
        }

        bool success = LibOptim.call(call.to, call.value, gasLimit == 0 ? gasleft() : gasLimit, call.data);
        if (!success) {
          if (call.behaviorOnError == Payload.BEHAVIOR_IGNORE_ERROR) {
            errorFlag = true;
            emit Calls.CallFailed(hydratableOpHash, i, LibOptim.returnData());
            continue;
          }

          if (call.behaviorOnError == Payload.BEHAVIOR_REVERT_ON_ERROR) {
            revert Calls.Reverted(decoded, i, LibOptim.returnData());
          }

          if (call.behaviorOnError == Payload.BEHAVIOR_ABORT_ON_ERROR) {
            emit Calls.CallAborted(hydratableOpHash, i, LibOptim.returnData());
            break;
          }
        }

        emit Calls.CallSucceeded(hydratableOpHash, i);
      }
    }
  }

  function _firstHydrateCall(bytes calldata hydratePayload) internal pure returns (uint256 rindex, uint256 tindex) {
    unchecked {
      if (hydratePayload.length == 0) {
        return (0, type(uint256).max);
      }

      return (1, uint256(uint8(hydratePayload[0])));
    }
  }

  function _hydrate(Payload.Decoded memory decoded, bytes calldata hydratePayload, uint256 rindex, uint256 tindex)
    internal
    view
    returns (uint256 nrindex, uint256 ntindex)
  {
    uint256 flag;
    uint256 cindex;

    while (true) {
      (flag, rindex) = hydratePayload.readUint8(rindex);

      if (flag == SIGNAL_NEXT_HYDRATE) {
        break;
      }

      if (flag <= HYDRATE_DATA_ANY_ADDRESS_TOKEN_BALANCE) {
        // Data-hydration commands mutate `decoded.calls[tindex].data` in-place.
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
        // Mutate the call recipient (`to`) to the message sender.
        decoded.calls[tindex].to = msg.sender;
      } else if (flag == HYDRATE_TO_TRANSACTION_ORIGIN_ADDRESS) {
        // Mutate the call recipient (`to`) to the transaction origin.
        decoded.calls[tindex].to = tx.origin;
      } else if (flag == HYDRATE_AMOUNT_SELF_BALANCE) {
        // Mutate the call value (`value`) to this contract's full ETH balance.
        decoded.calls[tindex].value = address(this).balance;
      } else {
        revert UnknownHydrateDataCommand(flag);
      }
    }

    // If present, the next byte is the next `tindex` (call index) to hydrate.
    if (rindex < hydratePayload.length) {
      tindex = uint256(uint8(hydratePayload[rindex]));
      rindex++;
    } else {
      // No more hydration sections.
      tindex = type(uint256).max;
    }

    return (rindex, tindex);
  }

}
