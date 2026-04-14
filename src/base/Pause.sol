// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Pausable as OZPausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {Authority} from "src/base/Authority.sol";
import {IPause} from "src/base/IPause.sol";

/// @title Pause
/// @notice Shares a single OpenZeppelin pause state across TrailsUtils modules.
abstract contract Pause is OZPausable, Authority, IPause {
  constructor(address initialOwner) Authority(initialOwner) {}

  function paused() public view virtual override(OZPausable, IPause) returns (bool) {
    if (address(this) == SELF) {
      return super.paused();
    }

    return IPause(SELF).paused();
  }

  function pause() external onlyDirectCall onlyOwnerOrOperator whenNotPaused {
    _pause();
  }

  function unpause() external onlyDirectCall onlyOwner whenPaused {
    _unpause();
  }
}
