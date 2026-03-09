// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Allowlist is Ownable {
  error ZeroAddress();
  error AlreadyAllowed(address addr);
  error NotAllowed(address addr);
  error IndexMismatch(uint256 index, address expected, address actual);

  mapping(address => bool) private _allowed;
  address[] private _entries;

  event AddressAdded(address indexed addr);
  event AddressRemoved(address indexed addr);

  constructor(address owner_, address[] memory initial) Ownable(owner_) {
    for (uint256 i; i < initial.length; i++) {
      address addr = initial[i];
      if (addr == address(0)) revert ZeroAddress();
      if (_allowed[addr]) revert AlreadyAllowed(addr);

      _allowed[addr] = true;
      _entries.push(addr);
    }
  }

  function add(address addr) external onlyOwner {
    if (addr == address(0)) revert ZeroAddress();
    if (_allowed[addr]) revert AlreadyAllowed(addr);
    _allowed[addr] = true;
    _entries.push(addr);
    emit AddressAdded(addr);
  }

  function remove(address addr, uint256 index) external onlyOwner {
    if (!_allowed[addr]) revert NotAllowed(addr);
    _allowed[addr] = false;

    if (index != 0) {
      if (_entries[index] != addr) revert IndexMismatch(index, addr, _entries[index]);
      _entries[index] = _entries[_entries.length - 1];
      _entries.pop();
    } else {
      // Search for the address
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

  function isAllowed(address addr) external view returns (bool) {
    return _allowed[addr];
  }

  function getAllowed() external view returns (address[] memory) {
    return _entries;
  }
}
