// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

/// @notice Helpers for decoding ABI-encoded calldata without copying.
library CalldataDecode {
  /// @notice Decodes ABI `(bytes,bytes)` from `data` into calldata slices.
  /// @dev Reverts with empty data on malformed input.
  function decodeBytesBytes(bytes calldata data) internal pure returns (bytes calldata a, bytes calldata b) {
    assembly ("memory-safe") {
      let base := data.offset
      let len := data.length

      // Need at least 2 words for the head (offsets).
      if lt(len, 64) { revert(0, 0) }

      // Read offsets (relative to `base`).
      let aRel := calldataload(base)
      let bRel := calldataload(add(base, 32))

      // ABI offsets are word-aligned and point into the tail.
      if or(and(aRel, 31), and(bRel, 31)) { revert(0, 0) }
      if or(lt(aRel, 64), lt(bRel, 64)) { revert(0, 0) }

      // Validate and materialize `a`.
      let aLenPtrRel := aRel
      let aDataRel := add(aLenPtrRel, 32)
      if or(gt(aDataRel, len), lt(aDataRel, aLenPtrRel)) { revert(0, 0) }
      let aLen := calldataload(add(base, aLenPtrRel))
      let aEndRel := add(aDataRel, aLen)
      if or(gt(aEndRel, len), lt(aEndRel, aDataRel)) { revert(0, 0) }

      // Validate and materialize `b`.
      let bLenPtrRel := bRel
      let bDataRel := add(bLenPtrRel, 32)
      if or(gt(bDataRel, len), lt(bDataRel, bLenPtrRel)) { revert(0, 0) }
      let bLen := calldataload(add(base, bLenPtrRel))
      let bEndRel := add(bDataRel, bLen)
      if or(gt(bEndRel, len), lt(bEndRel, bDataRel)) { revert(0, 0) }

      a.offset := add(base, aDataRel)
      a.length := aLen
      b.offset := add(base, bDataRel)
      b.length := bLen
    }
  }
}

