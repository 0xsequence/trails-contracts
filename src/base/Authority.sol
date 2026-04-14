// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Storage} from "wallet-contracts-v3/modules/Storage.sol";
import {Self} from "src/base/Self.sol";

/// @title Authority
/// @notice Owner/operator authority shared across TrailsUtils modules.
abstract contract Authority is Self {
  error UnauthorizedAccount(address account);
  error InvalidOwner(address owner);
  error OnlyDirectCallAllowed();

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  event OperatorUpdated(address indexed account, bool allowed);

  bytes32 private constant OWNER_KEY = keccak256("sequence.trails.utils.authority.owner");
  bytes32 private constant OPERATOR_KEY = keccak256("sequence.trails.utils.authority.operator");

  constructor(address initialOwner) {
    if (initialOwner == address(0)) {
      revert InvalidOwner(address(0));
    }

    _writeOwner(initialOwner);
    emit OwnershipTransferred(address(0), initialOwner);
  }

  modifier onlyDirectCall() {
    if (address(this) != SELF) {
      revert OnlyDirectCallAllowed();
    }
    _;
  }

  modifier onlyOwner() {
    if (msg.sender != _ownerDirect()) {
      revert UnauthorizedAccount(msg.sender);
    }
    _;
  }

  modifier onlyOwnerOrOperator() {
    address sender = msg.sender;
    if (sender != _ownerDirect() && !_isOperatorDirect(sender)) {
      revert UnauthorizedAccount(sender);
    }
    _;
  }

  function owner() public view returns (address) {
    if (address(this) == SELF) {
      return _ownerDirect();
    }

    return Authority(SELF).owner();
  }

  function isOperator(address account) public view returns (bool) {
    if (address(this) == SELF) {
      return _isOperatorDirect(account);
    }

    return Authority(SELF).isOperator(account);
  }

  function transferOwnership(address newOwner) external onlyDirectCall onlyOwner {
    if (newOwner == address(0)) {
      revert InvalidOwner(address(0));
    }

    address previousOwner = _ownerDirect();
    _writeOwner(newOwner);
    emit OwnershipTransferred(previousOwner, newOwner);
  }

  function setOperator(address account, bool allowed) external onlyDirectCall onlyOwner {
    _writeOperator(account, allowed);
    emit OperatorUpdated(account, allowed);
  }

  function _ownerDirect() private view returns (address) {
    return address(uint160(uint256(Storage.readBytes32(OWNER_KEY))));
  }

  function _writeOwner(address newOwner) private {
    Storage.writeBytes32(OWNER_KEY, bytes32(uint256(uint160(newOwner))));
  }

  function _isOperatorDirect(address account) private view returns (bool) {
    return Storage.readBytes32Map(OPERATOR_KEY, bytes32(uint256(uint160(account)))) != bytes32(0);
  }

  function _writeOperator(address account, bool allowed) private {
    Storage.writeBytes32Map(
      OPERATOR_KEY, bytes32(uint256(uint160(account))), allowed ? bytes32(uint256(1)) : bytes32(0)
    );
  }
}
