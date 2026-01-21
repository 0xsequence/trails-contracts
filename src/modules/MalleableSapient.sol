// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {LibBytes} from "wallet-contracts-v3/utils/LibBytes.sol";
import {LibOptim} from "wallet-contracts-v3/utils/LibOptim.sol";

/// @title MalleableSapient
/// @notice An `ISapient` implementation that lets the caller declare which parts of a transaction bundle are "static" (committed to),
/// which parts are "malleable" (can be changed/hydrated at execution), and which parts are "repeatable" (for malleable sections that must match).
/// @dev The returned `imageHash` is a rolling hash of:
/// - the payload `space` + `nonce`
/// - the current `block.chainid`
/// - each call's metadata (everything except `data`)
/// - each "static section" of call `data` as described by `signature`
/// - `tindex` (uint8): call index in `payload.calls` (top bit `0`)
/// - `cindex` (uint16): byte offset into `payload.calls[tindex].data`
/// - `size`  (uint16): byte length of the static section
/// - each "repeat section" is described by:
/// - `tindex` (uint8): call index in `payload.calls` (top bit `1`)
/// - `cindex` (uint16): byte offset into `payload.calls[tindex].data`
/// - `tindex2` (uint8): call index in `payload.calls`
/// - `cindex2` (uint16): byte offset into `payload.calls[tindex2].data`
/// - `size`  (uint16): byte length of the repeat section
/// - This is *not* an ECDSA signature; it's a compact description of the committed sections.
contract MalleableSapient is ISapient {
  error NonTransactionPayload();

  error InvalidRepeatSection(uint256 _tindex, uint256 _cindex, uint256 _size, uint256 _tindex2, uint256 _cindex2);

  using LibBytes for bytes;

  /// @inheritdoc ISapient
  /// @dev Computes the `imageHash` for a transaction payload with a malleable `data` commitment.
  function recoverSapientSignature(Payload.Decoded calldata payload, bytes calldata signature)
    external
    view
    returns (bytes32 imageHash)
  {
    if (payload.kind != Payload.KIND_TRANSACTIONS) {
      revert NonTransactionPayload();
    }

    // Roll space and nonce
    bytes32 root = LibOptim.fkeccak256(bytes32(payload.space), bytes32(payload.nonce));

    // Roll chainId
    if (payload.noChainId) {
      root = LibOptim.fkeccak256(root, bytes32(0));
    } else {
      root = LibOptim.fkeccak256(root, bytes32(block.chainid));
    }

    unchecked {
      // Roll all calls except their `data`
      for (uint256 i = 0; i < payload.calls.length; i++) {
        Payload.Call calldata call = payload.calls[i];
        root = LibOptim.fkeccak256(
          root,
          keccak256(
            abi.encode(
              "call", i, call.to, call.value, call.gasLimit, call.delegateCall, call.onlyFallback, call.behaviorOnError
            )
          )
        );
      }

      uint256 rindex;
      uint256 tindex;
      uint256 tindex2;
      uint256 cindex;
      uint256 cindex2;
      uint256 size;

      while (rindex < signature.length) {
        (tindex, rindex) = signature.readUint8(rindex);
        (cindex, rindex) = signature.readUint16(rindex);
        (size, rindex) = signature.readUint16(rindex);

        // Top bit of tindex indicates whether this is a "repeat-section" or a "static-section"
        bool repeatSection = (tindex & 0x80) != 0;
        tindex = tindex & 0x7F;

        bytes calldata section = payload.calls[tindex].data[cindex:cindex + size];

        if (repeatSection) {
          // Ensure a section is repeated
          (tindex2, rindex) = signature.readUint8(rindex);
          (cindex2, rindex) = signature.readUint16(rindex);

          bytes calldata section2 = payload.calls[tindex2].data[cindex2:cindex2 + size];
          if (keccak256(section) != keccak256(section2)) {
            revert InvalidRepeatSection(tindex, cindex, size, tindex2, cindex2);
          }

          root = LibOptim.fkeccak256(root, _repeatSection(tindex, cindex, size, tindex2, cindex2));
        } else {
          // Roll only the data defined as static, everything else is malleable
          root = LibOptim.fkeccak256(root, _staticSection(tindex, cindex, section));
        }
      }

      return root;
    }
  }

  function _repeatSection(uint256 _tindex, uint256 _cindex, uint256 _size, uint256 _tindex2, uint256 _cindex2)
    internal
    pure
    returns (bytes32)
  {
    return keccak256(abi.encode("repeat-section", _tindex, _cindex, _size, _tindex2, _cindex2));
  }

  function _staticSection(uint256 _tindex, uint256 _cindex, bytes calldata _data) internal pure returns (bytes32) {
    return keccak256(abi.encode("static-section", _tindex, _cindex, _data));
  }
}
