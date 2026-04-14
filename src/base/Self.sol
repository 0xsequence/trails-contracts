// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

abstract contract Self {
  address internal immutable SELF = address(this);
}
