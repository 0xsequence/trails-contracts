// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Allowlist
/// @notice Owner-managed set of addresses allowed to authorize timed refund batches.
contract Allowlist is Ownable {
  /// @notice A zero address was provided where a signer address is required.
  error ZeroAddress();
  /// @notice The address is already present in the allowlist.
  error AlreadyAllowed(address addr);
  /// @notice The address is not present in the allowlist.
  error NotAllowed(address addr);
  /// @notice The provided index hint does not point at the expected address.
  error IndexMismatch(uint256 index, address expected, address actual);

  mapping(address => bool) private _allowed;
  address[] private _entries;

  /// @notice Emitted when an address is added to the allowlist.
  event AddressAdded(address indexed addr);
  /// @notice Emitted when an address is removed from the allowlist.
  event AddressRemoved(address indexed addr);

  /// @notice Initializes the allowlist owner and optional initial entries.
  /// @param owner_ The account allowed to mutate the allowlist.
  /// @param initial The initial addresses to mark as allowed.
  constructor(address owner_, address[] memory initial) Ownable(owner_) {
    for (uint256 i; i < initial.length; i++) {
      _add(initial[i]);
    }
  }

  /// @notice Adds `addr` to the allowlist.
  /// @param addr The address to add.
  function add(address addr) external onlyOwner {
    _add(addr);
  }

  /// @notice Adds each address in `addrs` to the allowlist.
  /// @param addrs The addresses to add.
  function add(address[] calldata addrs) external onlyOwner {
    for (uint256 i; i < addrs.length; i++) {
      _add(addrs[i]);
    }
  }

  /// @notice Removes `addr` from the allowlist.
  /// @param addr The address to remove.
  /// @param index Optional index hint into `getAllowed()`. Pass `0` to use search mode.
  /// @dev Removal uses swap-and-pop, so `getAllowed()` ordering is not stable.
  function remove(address addr, uint256 index) external onlyOwner {
    _remove(addr, index);
  }

  /// @notice Removes each address in `addrs` from the allowlist using search mode.
  /// @param addrs The addresses to remove.
  /// @dev Removal uses swap-and-pop, so `getAllowed()` ordering is not stable.
  function remove(address[] calldata addrs) external onlyOwner {
    for (uint256 i; i < addrs.length; i++) {
      _remove(addrs[i], 0);
    }
  }

  /// @notice Returns whether `addr` is currently allowed.
  function isAllowed(address addr) external view returns (bool) {
    return _allowed[addr];
  }

  /// @notice Returns the current allowlist entries in storage order.
  /// @dev Ordering is not stable because removals use swap-and-pop.
  function getAllowed() external view returns (address[] memory) {
    return _entries;
  }

  function _add(address addr) private {
    if (addr == address(0)) revert ZeroAddress();
    if (_allowed[addr]) revert AlreadyAllowed(addr);

    _allowed[addr] = true;
    _entries.push(addr);

    emit AddressAdded(addr);
  }

  function _remove(address addr, uint256 index) private {
    if (!_allowed[addr]) revert NotAllowed(addr);
    _allowed[addr] = false;

    if (index != 0) {
      if (_entries[index] != addr) revert IndexMismatch(index, addr, _entries[index]);
      _entries[index] = _entries[_entries.length - 1];
      _entries.pop();
    } else {
      uint256 len = _entries.length;
      for (uint256 i; i < len; i++) {
        if (_entries[i] == addr) {
          _entries[i] = _entries[len - 1];
          _entries.pop();
          break;
        }
      }
    }

    emit AddressRemoved(addr);
  }
}
