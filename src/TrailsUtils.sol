// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {MalleableSapient} from "src/modules/MalleableSapient.sol";
import {HydrateProxy} from "src/modules/HydrateProxy.sol";
import {RequireUtils} from "src/modules/RequireUtils.sol";
import {Pause} from "src/base/Pause.sol";
import {IPause} from "src/base/IPause.sol";

/// @title TrailsUtils
/// @notice Convenience contract that bundles multiple utility modules under a single deployed address.
/// @dev This contract intentionally contains no additional logic; it simply inherits:
/// - {MalleableSapient} for malleable commitments
/// - {HydrateProxy} for hydrate + execute flows
/// - {RequireUtils} for precondition checks
contract TrailsUtils is Pause, MalleableSapient, HydrateProxy, RequireUtils {
  constructor(address initialOwner) Pause(initialOwner) {}

  function paused() public view override(Pause, IPause) returns (bool) {
    return Pause.paused();
  }
}
