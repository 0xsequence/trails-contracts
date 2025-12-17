// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {MalleableSapient} from "src/modules/MalleableSapient.sol";
import {SharedProxy} from "src/modules/SharedProxy.sol";
import {RequireUtils} from "src/modules/RequireUtils.sol";

/**
 * @title TrailsUtils
 * @notice Convenience contract that bundles multiple utility modules under a single deployed address.
 * @dev
 * This contract intentionally contains no additional logic; it simply inherits:
 * - {MalleableSapient} for malleable commitments
 * - {SharedProxy} for hydrate + execute flows
 * - {RequireUtils} for precondition checks
 */
contract TrailsUtils is MalleableSapient, SharedProxy, RequireUtils {}
