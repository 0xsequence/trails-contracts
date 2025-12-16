// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {MalleableSapient} from "src/modules/MalleableSapient.sol";
import {SharedProxy} from "src/modules/SharedProxy.sol";
import {RequireUtils} from "src/modules/RequireUtils.sol";

// Combine all tools in one so we don't have to touch different addresses when processing an intent.
contract TrailsUtils is MalleableSapient, SharedProxy, RequireUtils { }