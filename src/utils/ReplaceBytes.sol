// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

/// @notice Helpers for mutating `bytes` in-place.
/// @dev Reverts with empty data on out-of-bounds writes.
library ReplaceBytes {
  /// @notice Overwrites 20 bytes at `offset` with `addr`, in-place.
  /// @dev Writes the raw 20-byte address (i.e. `abi.encodePacked(addr)`), not ABI-padded.
  ///      Safe for any `offset` (word-aligned or not) and does not allocate a new array.
  function replaceAddress(bytes memory data, uint256 offset, address addr) internal pure {
    assembly {
      // Bounds check (also catches `offset + 20` overflow).
      let len := mload(data)
      let end := add(offset, 20)
      if or(gt(end, len), lt(end, offset)) { revert(0, 0) }

      // Calculate the pointer to the data (skipping the length prefix)
      let ptr := add(add(data, 32), offset)

      // Load the 32 bytes currently at that position
      let currentWord := mload(ptr)

      // Clean the address and shift it to the top 20 bytes
      let addrBytes := shl(96, addr)

      // Combine: (New Address) OR (Old Ending Bytes)
      let result := or(addrBytes, and(currentWord, 0xFFFFFFFFFFFFFFFFFFFFFFFF))

      // Store the result back (EVM allows unaligned stores)
      mstore(ptr, result)
    }
  }

  /// @notice Overwrites 32 bytes at `offset` with `val`, in-place.
  /// @dev Writes the raw 32-byte word (i.e. `abi.encodePacked(val)`), and does not allocate a new array.
  function replaceUint256(bytes memory data, uint256 offset, uint256 val) internal pure {
    assembly {
      // Bounds check (also catches `offset + 32` overflow).
      let len := mload(data)
      let end := add(offset, 32)
      if or(gt(end, len), lt(end, offset)) { revert(0, 0) }

      mstore(add(add(data, 32), offset), val)
    }
  }
}
