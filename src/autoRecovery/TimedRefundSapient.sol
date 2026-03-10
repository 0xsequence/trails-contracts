// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Allowlist} from "./Allowlist.sol";

/// @title TimedRefundSapient
/// @notice Sapient signer that authorizes time-locked refund batches to a fixed destination.
/// @dev The returned image hash commits to `(destination, unlockTimestamp)` and only approves
/// plain native transfers or ERC20 `transfer(address,uint256)` calls to that destination.
contract TimedRefundSapient is ISapient {
  /// @notice Dedicated nonce space for timed refund payloads.
  /// @dev uint160(uint256(keccak256("trails.timed-refund.nonce-space")) | (uint256(1) << 159))
  uint256 public constant TIMED_REFUND_NONCE_SPACE = uint256(uint160(0xeF25450978071B7bD3a1aFE58C4484c84B31FaF8));

  bytes4 private constant ERC20_TRANSFER_SELECTOR = IERC20.transfer.selector;
  uint256 private constant COMPACT_SIGNATURE_LENGTH = 64;

  /// @notice Allowlist of signers permitted to authorize timed refund batches.
  Allowlist public immutable allowlist;

  /// @notice The payload contains a call outside the approved transfer-only surface.
  error UnauthorizedTransaction(uint256 index);
  /// @notice The recovered signer is not currently allowlisted.
  error SignerNotAllowed(address signer);
  /// @notice The unlock timestamp has not been reached yet.
  error UnlockTimestampNotReached(uint256 unlockTimestamp, uint256 timestamp);
  /// @notice The sapient signer only supports transaction payloads.
  error InvalidPayloadKind(uint8 kind);
  /// @notice The payload used a nonce space outside the dedicated timed refund lane.
  error InvalidNonceSpace(uint256 space, uint256 expected);
  /// @notice The compact approval signature has an unexpected length.
  error InvalidApprovalSignatureLength(uint256 length);
  /// @notice The compact approval signature did not recover a signer.
  error InvalidRecoveredSigner();
  /// @notice A call used an unsupported `behaviorOnError` mode.
  error InvalidBehaviorOnError(uint256 index, uint256 behaviorOnError);
  /// @notice Delegate calls are not allowed in timed refund payloads.
  error DelegateCallNotAllowed(uint256 index);
  /// @notice Fallback-only calls are not allowed in timed refund payloads.
  error OnlyFallbackNotAllowed(uint256 index);
  /// @notice Per-call gas limits are not allowed in timed refund payloads.
  error GasLimitNotZero(uint256 index, uint256 gasLimit);
  /// @notice Native transfers must not include calldata.
  error NativeTransferDataNotEmpty(uint256 index, uint256 dataLength);

  /// @notice Initializes the sapient signer with its signer allowlist.
  /// @param allowlist_ The owner-managed allowlist of refund authorizers.
  constructor(Allowlist allowlist_) {
    allowlist = allowlist_;
  }

  function _rootForTimedRefund(address destination, uint256 unlockTimestamp) internal pure returns (bytes32) {
    return keccak256(abi.encode("timed-refund", destination, unlockTimestamp));
  }

  function _recoverCompactSigner(bytes32 hash, bytes memory signature) internal pure returns (address) {
    bytes32 r;
    bytes32 s;
    uint8 v;

    assembly {
      r := mload(add(signature, 0x20))
      let yParityAndS := mload(add(signature, 0x40))
      v := add(shr(255, yParityAndS), 27)
      s := and(yParityAndS, sub(shl(255, 1), 1))
    }

    return ecrecover(hash, v, r, s);
  }

  /// @notice Returns whether `token` responds to the ERC20 metadata probes.
  /// @dev This is a lightweight heuristic used to distinguish token-like transfers from native transfers.
  function hasERC20Metadata(address token) public view returns (bool) {
    return _hasNonEmptyResponse(token, abi.encodeCall(IERC20Metadata.name, ()))
      && _hasNonEmptyResponse(token, abi.encodeCall(IERC20Metadata.symbol, ()));
  }

  function _hasNonEmptyResponse(address target, bytes memory callData) private view returns (bool) {
    (bool success, bytes memory returndata) = target.staticcall(callData);
    return success && returndata.length != 0;
  }

  /// @inheritdoc ISapient
  /// @dev `signature` is ABI-encoded as `(address destination, uint256 unlockTimestamp, bytes compactSignature)`.
  function recoverSapientSignature(Payload.Decoded calldata payload, bytes calldata signature)
    external
    view
    returns (bytes32 imageHash)
  {
    (address destination, uint256 unlockTimestamp, bytes memory approvalSignature) =
      abi.decode(signature, (address, uint256, bytes));
    if (approvalSignature.length != COMPACT_SIGNATURE_LENGTH) {
      revert InvalidApprovalSignatureLength(approvalSignature.length);
    }

    if (payload.kind != Payload.KIND_TRANSACTIONS) revert InvalidPayloadKind(payload.kind);
    if (payload.space != TIMED_REFUND_NONCE_SPACE) {
      revert InvalidNonceSpace(payload.space, TIMED_REFUND_NONCE_SPACE);
    }

    address signer = _recoverCompactSigner(Payload.hashFor(payload, msg.sender), approvalSignature);
    if (signer == address(0)) revert InvalidRecoveredSigner();
    if (!allowlist.isAllowed(signer)) revert SignerNotAllowed(signer);
    if (block.timestamp < unlockTimestamp) revert UnlockTimestampNotReached(unlockTimestamp, block.timestamp);

    // Restrict the approved surface to direct transfers into `destination`.
    for (uint256 i = 0; i < payload.calls.length; i++) {
      Payload.Call calldata call = payload.calls[i];
      if (call.behaviorOnError != Payload.BEHAVIOR_REVERT_ON_ERROR) {
        revert InvalidBehaviorOnError(i, call.behaviorOnError);
      }
      if (call.delegateCall) revert DelegateCallNotAllowed(i);
      if (call.onlyFallback) revert OnlyFallbackNotAllowed(i);
      if (call.gasLimit != 0) revert GasLimitNotZero(i, call.gasLimit);

      bytes calldata data = call.data;

      if (call.value == 0) {
        if (!hasERC20Metadata(call.to)) revert UnauthorizedTransaction(i);
        // ERC20 transfer(address,uint256) to `destination`.
        if (data.length != 68) revert UnauthorizedTransaction(i);
        if (bytes4(data[:4]) != ERC20_TRANSFER_SELECTOR) revert UnauthorizedTransaction(i);
        if (bytes32(data[4:36]) != bytes32(uint256(uint160(destination)))) revert UnauthorizedTransaction(i);
      } else {
        // Native transfer to `destination`.
        if (call.to != destination) revert UnauthorizedTransaction(i);
        if (data.length != 0) revert NativeTransferDataNotEmpty(i, data.length);
      }
    }

    return _rootForTimedRefund(destination, unlockTimestamp);
  }
}
