// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {MalleableSapient} from "src/modules/MalleableSapient.sol";
import {HydrateProxy} from "src/modules/HydrateProxy.sol";
import {RequireUtils} from "src/modules/RequireUtils.sol";

/**
 * @title TrailsUtils
 * @notice Convenience contract that bundles multiple utility modules under a single deployed address.
 * @dev
 * This contract intentionally contains no additional logic; it simply inherits:
 * - {MalleableSapient} for malleable commitments
 * - {HydrateProxy} for hydrate + execute flows
 * - {RequireUtils} for precondition checks
 */
contract TrailsUtils is MalleableSapient, HydrateProxy, RequireUtils {}
