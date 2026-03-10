// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {Allowlist} from "./Allowlist.sol";


contract AutoRecoverSapient is ISapient {
  Allowlist immutable ALLOWLIST;

  uint256 private constant COMPACT_SIGNATURE_LENGTH = 64;

  constructor (Allowlist _allowlist) {
    ALLOWLIST = _allowlist;
  }

  error UnauthorizedTransaction(uint256 _i);
  error SignerNotAllowed(address _signer);
  error ThresholdNotReached(uint256 _threshold, uint256 _timestamp);
  error InvalidPayloadKind(uint8 _kind);
  error InvalidAllowSignatureLength(uint256 _length);
  error InvalidRecoveredSigner();
  error InvalidBehaviorOnError(uint256 _i, uint256 _behaviorOnError);
  error DelegateCallNotAllowed(uint256 _i);
  error OnlyFallbackNotAllowed(uint256 _i);
  error GasLimitNotZero(uint256 _i, uint256 _gasLimit);
  error NativeTransferDataNotEmpty(uint256 _i, uint256 _dataLength);

  function _rootForAutoRecover(
    address _destination,
    uint256 _threshold
  ) internal pure returns (bytes32) {
    return keccak256(abi.encode("auto-recover", _destination, _threshold));
  }

  function recoverSigner(bytes32 _hash, bytes memory _signature) internal pure returns (address) {
    bytes32 r;
    bytes32 s;
    uint8 v;

    assembly {
      r := mload(add(_signature, 0x20))
      let yParityAndS := mload(add(_signature, 0x40))
      v := add(shr(255, yParityAndS), 27)
      s := and(yParityAndS, sub(shl(255, 1), 1))
    }

    return ecrecover(_hash, v, r, s);
  }

  function recoverSapientSignature(Payload.Decoded calldata payload, bytes calldata signature)
    external
    view
    returns (bytes32 imageHash)
  {
    (address destination, uint256 threshold, bytes memory allowSignature) = abi.decode(signature, (address, uint256, bytes));
    if (allowSignature.length != COMPACT_SIGNATURE_LENGTH) revert InvalidAllowSignatureLength(allowSignature.length);

    address signer = recoverSigner(Payload.hashFor(payload, msg.sender), allowSignature);
    if (signer == address(0)) revert InvalidRecoveredSigner();
    if (!ALLOWLIST.isAllowed(signer)) revert SignerNotAllowed(signer);
    if (block.timestamp < threshold) revert ThresholdNotReached(threshold, block.timestamp);

    // Verify if payload is exclusively composed of transfers to owner
    // either ERC20s or native transfers
    if (payload.kind != Payload.KIND_TRANSACTIONS) revert InvalidPayloadKind(payload.kind);
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
        // Must be an ERC20 transfer to "destination"
        if (data.length != 68) revert UnauthorizedTransaction(i);
        // Check selector is transfer(address,uint256) = 0xa9059cbb
        if (bytes4(data[:4]) != bytes4(0xa9059cbb)) revert UnauthorizedTransaction(i);
        // Check destination matches (ABI-encoded as a full 32-byte word)
        if (bytes32(data[4:36]) != bytes32(uint256(uint160(destination)))) revert UnauthorizedTransaction(i);
      } else {
        // Native transfer: recipient must be "destination"
        if (call.to != destination) revert UnauthorizedTransaction(i);
        if (data.length != 0) revert NativeTransferDataNotEmpty(i, data.length);
      }
    }

    return _rootForAutoRecover(destination, threshold);
  }
}
