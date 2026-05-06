// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title Pausable
/// @notice Owner-controlled pause state with additional operators that may only pause.
abstract contract Pausable is Ownable {
  using EnumerableSet for EnumerableSet.AddressSet;

  /// @notice The zero address was provided where an operator address is required.
  error ZeroAddress();
  /// @notice The caller is neither the owner nor a pause operator.
  error UnauthorizedPauser(address account);
  /// @notice The contract is paused.
  error EnforcedPause();
  /// @notice The contract is not paused.
  error ExpectedPause();
  /// @notice Ownership renunciation is disabled to keep pause recovery available.
  error OwnershipRenunciationDisabled();

  EnumerableSet.AddressSet private _operators;
  /// @notice Returns whether the contract is currently paused.
  bool public paused;

  /// @notice Emitted when `account` pauses the contract.
  event Paused(address indexed account);
  /// @notice Emitted when `account` unpauses the contract.
  event Unpaused(address indexed account);
  /// @notice Emitted when an operator permission is updated.
  event OperatorSet(address indexed operator, bool allowed);

  /// @notice Initializes the owner and optional initial pause operators.
  /// @param owner_ The owner allowed to manage operators and unpause.
  /// @param initialOperators The initial set of addresses allowed to pause.
  constructor(address owner_, address[] memory initialOperators) Ownable(owner_) {
    for (uint256 i; i < initialOperators.length; i++) {
      _setOperator(initialOperators[i], true);
    }
  }

  /// @notice Reverts when the contract is paused.
  modifier whenNotPaused() {
    if (paused) {
      revert EnforcedPause();
    }
    _;
  }

  /// @notice Reverts when the contract is not paused.
  modifier whenPaused() {
    if (!paused) {
      revert ExpectedPause();
    }
    _;
  }

  /// @notice Pauses the contract.
  /// @dev Callable by the owner or an approved operator.
  function pause() external whenNotPaused {
    if (msg.sender != owner() && !_operators.contains(msg.sender)) {
      revert UnauthorizedPauser(msg.sender);
    }

    paused = true;
    emit Paused(msg.sender);
  }

  /// @notice Unpauses the contract.
  /// @dev Callable only by the owner.
  function unpause() external onlyOwner whenPaused {
    paused = false;
    emit Unpaused(msg.sender);
  }

  /// @notice Updates whether `operator` is allowed to pause.
  /// @param operator The address to update.
  /// @param allowed Whether the address may pause.
  function setOperator(address operator, bool allowed) external onlyOwner {
    _setOperator(operator, allowed);
  }

  /// @notice Returns whether `account` is allowed to pause.
  function isOperator(address account) external view returns (bool) {
    return _operators.contains(account);
  }

  /// @notice Returns the current pause operators in storage order.
  /// @dev Ordering is not guaranteed and may change when operators are removed.
  function getOperators() external view returns (address[] memory) {
    return _operators.values();
  }

  /// @notice Disables ownership renunciation to avoid permanently locked pause state.
  function renounceOwnership() public view override onlyOwner {
    revert OwnershipRenunciationDisabled();
  }

  function _setOperator(address operator, bool allowed) private {
    if (operator == address(0)) {
      revert ZeroAddress();
    }

    if (allowed) {
      _operators.add(operator);
    } else {
      _operators.remove(operator);
    }

    emit OperatorSet(operator, allowed);
  }
}
