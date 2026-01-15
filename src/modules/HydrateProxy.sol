// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {Sweepable} from "src/modules/Sweepable.sol";
import {CalldataDecode} from "src/utils/CalldataDecode.sol";
import {ReplaceBytes} from "src/utils/ReplaceBytes.sol";
import {LibBytes} from "wallet-contracts-v3/utils/LibBytes.sol";
import {IDelegatedExtension} from "wallet-contracts-v3/modules/interfaces/IDelegatedExtension.sol";
import {Calls} from "wallet-contracts-v3/modules/Calls.sol";
import {LibOptim} from "wallet-contracts-v3/utils/LibOptim.sol";

/// @title HydrateProxy
/// @notice A minimal execution proxy that "hydrates" a batch payload at execution time and then executes it.
/// @dev This is designed for intent flows where:
/// - The call bundle must be created/quoted off-chain.
/// - Some values (balances, runtime addresses, etc.) are only known at execution time.
contract HydrateProxy is Sweepable, IDelegatedExtension {
  using LibBytes for bytes;
  using ReplaceBytes for bytes;
  using CalldataDecode for bytes;

  /// @notice An unknown hydration type flag is encountered.
  error UnknownHydrateTypeCommand(uint256 flag);

  /// @notice An unknown hydration data flag is encountered.
  error UnknownHydrateDataCommand(uint256 flag);

  /// @notice Delegatecall is requested from the HydrateProxy's context.
  error DelegateCallNotAllowed(uint256 index);

  /// @notice Call context is required to be the HydrateProxy but is not.
  error OnlyDelegateCallAllowed();

  /// @notice Delegate call failed.
  error DelegateCallFailed(bytes result);

  // Hydration stream delimiter: ends the current call's hydration section.
  uint256 private constant SIGNAL_NEXT_HYDRATE = 0x00;

  // Hydration type flags
  uint256 private constant HYDRATE_TYPE_DATA_ADDRESS = 0x01;
  uint256 private constant HYDRATE_TYPE_DATA_BALANCE = 0x02;
  uint256 private constant HYDRATE_TYPE_DATA_ERC20_BALANCE = 0x03;
  uint256 private constant HYDRATE_TYPE_DATA_ERC20_ALLOWANCE = 0x04;
  uint256 private constant HYDRATE_TYPE_TO = 0x05;
  uint256 private constant HYDRATE_TYPE_VALUE = 0x06;

  // Hydration data flags
  uint256 private constant HYDRATE_DATA_SELF = 0x00;
  uint256 private constant HYDRATE_DATA_MESSAGE_SENDER = 0x01;
  uint256 private constant HYDRATE_DATA_TRANSACTION_ORIGIN = 0x02;
  uint256 private constant HYDRATE_DATA_ANY_ADDRESS = 0x03;

  // Cached address of this contract to detect delegatecall context.
  address internal immutable SELF = address(this);

  /// @notice Hydrates `packedPayload` using `hydratePayload` and then executes the batch.
  /// @param packedPayload The packed payload to hydrate.
  /// @param hydratePayload The hydrate payload to use.
  /// @dev `hydratePayload` is a byte stream grouped by call index:
  /// - Starts with a 1-byte `tindex` (the call to hydrate).
  /// - Followed by commands for that call. Each command starts with a 1-byte `flag`.
  /// - A `SIGNAL_NEXT_HYDRATE` (0x00) ends the current call's section; if more bytes remain, the next byte is the next `tindex`.
  /// - The supported command flags are the `HYDRATE_*` constants in this file.
  function hydrateExecute(bytes calldata packedPayload, bytes calldata hydratePayload) external payable {
    _hydrateExecute(packedPayload, hydratePayload);
  }

  /// @inheritdoc IDelegatedExtension
  /// @dev Delegate calls are allowed to all functions on this contract
  function handleSequenceDelegateCall(bytes32, uint256, uint256, uint256, uint256, bytes calldata data)
    external
    virtual
  {
    if (address(this) == SELF) {
      revert OnlyDelegateCallAllowed();
    }
    (bool success, bytes memory result) = SELF.delegatecall(data);
    if (!success) {
      revert DelegateCallFailed(result);
    }
  }

  /// @notice Hydrates and executes, then sweeps remaining funds to a recipient.
  /// @param packedPayload The packed payload to hydrate and execute.
  /// @param hydratePayload The hydrate payload to use.
  /// @param sweepTarget The address to sweep the remaining funds to.
  /// @param tokensToSweep Token list to sweep (each full balance of this contract).
  /// @param sweepNative Whether to sweep native tokens
  function hydrateExecuteAndSweep(
    bytes calldata packedPayload,
    bytes calldata hydratePayload,
    address sweepTarget,
    address[] calldata tokensToSweep,
    bool sweepNative
  ) external payable {
    _hydrateExecute(packedPayload, hydratePayload);
    _sweep(sweepTarget, tokensToSweep, sweepNative);
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

        if (call.delegateCall && address(this) == SELF) {
          // Delegatecall is not allowed from this contract context.
          revert DelegateCallNotAllowed(i);
        }

        bool success;
        if (call.delegateCall) {
          (success) = LibOptim.delegatecall(call.to, gasLimit == 0 ? gasleft() : gasLimit, call.data);
        } else {
          (success) = LibOptim.call(call.to, call.value, gasLimit == 0 ? gasleft() : gasLimit, call.data);
        }

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

      // Split top and bottom nibbles of the flag
      uint256 typeFlag = flag >> 4;
      uint256 valueFlag = flag & 0x0F;

      address valueAddress;
      (valueAddress, rindex) = _getAddressFromFlag(valueFlag, hydratePayload, rindex);

      if (typeFlag <= HYDRATE_TYPE_DATA_ERC20_ALLOWANCE) {
        // Data hydration commands mutate `decoded.calls[tindex].data` in-place.
        (cindex, rindex) = hydratePayload.readUint16(rindex);

        if (typeFlag == HYDRATE_TYPE_DATA_ADDRESS) {
          // Insert `address(this)` at `cindex` as a raw 20-byte address.
          decoded.calls[tindex].data.replaceAddress(cindex, valueAddress);
        } else if (typeFlag == HYDRATE_TYPE_DATA_BALANCE) {
          // Insert `address(this).balance` at `cindex` as a uint256.
          decoded.calls[tindex].data.replaceUint256(cindex, valueAddress.balance);
        } else if (typeFlag == HYDRATE_TYPE_DATA_ERC20_BALANCE) {
          // Insert this contract's ERC20 balance for a token read from hydratePayload.
          address token;
          (token, rindex) = hydratePayload.readAddress(rindex);
          decoded.calls[tindex].data.replaceUint256(cindex, IERC20(token).balanceOf(valueAddress));
        } else if (typeFlag == HYDRATE_TYPE_DATA_ERC20_ALLOWANCE) {
          // Insert this contract's ERC20 allowance for a token read from hydratePayload.
          address token;
          (token, rindex) = hydratePayload.readAddress(rindex);

          // Spender is data typed.
          uint256 spenderType;
          (spenderType, rindex) = hydratePayload.readUint8(rindex);
          address spender;
          (spender, rindex) = _getAddressFromFlag(spenderType, hydratePayload, rindex);

          decoded.calls[tindex].data.replaceUint256(cindex, IERC20(token).allowance(valueAddress, spender));
        }
      } else if (typeFlag == HYDRATE_TYPE_TO) {
        // Mutate the call recipient (`to`) to the message sender.
        decoded.calls[tindex].to = valueAddress;
      } else if (typeFlag == HYDRATE_TYPE_VALUE) {
        // Mutate the call value (`value`) to this contract's full ETH balance.
        decoded.calls[tindex].value = valueAddress.balance;
      } else {
        revert UnknownHydrateTypeCommand(typeFlag);
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

  function _getAddressFromFlag(uint256 flag, bytes calldata hydratePayload, uint256 rindex)
    internal
    view
    returns (address, uint256)
  {
    uint256 valueFlag = flag & 0x0F;
    if (valueFlag == HYDRATE_DATA_SELF) {
      return (address(this), rindex);
    } else if (valueFlag == HYDRATE_DATA_MESSAGE_SENDER) {
      return (msg.sender, rindex);
    } else if (valueFlag == HYDRATE_DATA_TRANSACTION_ORIGIN) {
      return (tx.origin, rindex);
    } else if (valueFlag == HYDRATE_DATA_ANY_ADDRESS) {
      address valueAddress;
      (valueAddress, rindex) = hydratePayload.readAddress(rindex);
      return (valueAddress, rindex);
    }
    revert UnknownHydrateDataCommand(valueFlag);
  }
}
