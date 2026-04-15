// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPause} from "src/base/IPause.sol";

/// @title Pausable
/// @notice Shares a single pause state plus owner/operator authority across TrailsUtils modules.
abstract contract Pausable is Ownable, IPause {
  error OnlyDirectCallAllowed();
  error ZeroAddress();
  error UnauthorizedPauser(address account);
  error ExpectedPause();

  event Paused(address indexed account);
  event Unpaused(address indexed account);
  event OperatorSet(address indexed operator, bool allowed);

  mapping(address => bool) private _operators;
  bool private _paused;

  constructor(address owner_, address[] memory initialOperators) Ownable(owner_) {
    for (uint256 i; i < initialOperators.length; i++) {
      address operator = initialOperators[i];
      if (operator == address(0)) {
        revert ZeroAddress();
      }

      _operators[operator] = true;
    }
  }

  modifier onlyDirectCall() {
    if (address(this) != SELF) {
      revert OnlyDirectCallAllowed();
    }
    _;
  }

  modifier whenNotPaused() {
    if (paused()) {
      revert EnforcedPause();
    }
    _;
  }

  modifier whenPaused() {
    if (!paused()) {
      revert ExpectedPause();
    }
    _;
  }

  function owner() public view override returns (address) {
    if (address(this) == SELF) {
      return super.owner();
    }

    return Pausable(SELF).owner();
  }

  function isOperator(address account) public view returns (bool) {
    if (address(this) == SELF) {
      return _operators[account];
    }

    return Pausable(SELF).isOperator(account);
  }

  function paused() public view virtual override returns (bool) {
    if (address(this) == SELF) {
      return _paused;
    }

    return IPause(SELF).paused();
  }

  function transferOwnership(address newOwner) public override onlyDirectCall onlyOwner {
    super.transferOwnership(newOwner);
  }

  function renounceOwnership() public pure override {
    revert OnlyDirectCallAllowed();
  }

  function setOperator(address operator, bool allowed) external onlyDirectCall onlyOwner {
    if (operator == address(0)) {
      revert ZeroAddress();
    }

    _operators[operator] = allowed;
    emit OperatorSet(operator, allowed);
  }

  function pause() external onlyDirectCall whenNotPaused {
    address sender = msg.sender;
    if (sender != owner() && !_operators[sender]) {
      revert UnauthorizedPauser(sender);
    }

    _paused = true;
    emit Paused(sender);
  }

  function unpause() external onlyDirectCall onlyOwner whenPaused {
    _paused = false;
    emit Unpaused(msg.sender);
  }
}
