// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Pausable as OZPausable} from "openzeppelin-contracts/contracts/utils/Pausable.sol";
import {Self} from "src/base/Self.sol";

abstract contract IPause is Self {
  modifier whenActive() {
    _requireActive();
    _;
  }

  function paused() public view virtual returns (bool) {
    if (address(this) == SELF) {
      return false;
    }

    return IPause(SELF).paused();
  }

  function _requireActive() internal view virtual {
    if (paused()) {
      revert OZPausable.EnforcedPause();
    }
  }
}
