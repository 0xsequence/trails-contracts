// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Self} from "src/base/Self.sol";

abstract contract IPause is Self {
  error EnforcedPause();

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
      revert EnforcedPause();
    }
  }
}
