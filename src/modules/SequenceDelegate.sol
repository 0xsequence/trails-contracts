// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDelegatedExtension} from "wallet-contracts-v3/modules/interfaces/IDelegatedExtension.sol";

/// @notice Abstract contract providing a reusable delegatecall-only guard.
contract SequenceDelegate is IDelegatedExtension {
  /// @dev Error thrown when a function expected to be delegatecalled is invoked directly
  error NotDelegateCall();

  /// @dev Cached address of this contract to detect delegatecall context
  address internal immutable _SELF = address(this);

  /// @dev Modifier restricting functions to only be executed via delegatecall
  modifier onlyDelegatecall() {
    _onlyDelegatecall();
    _;
  }

  /// @dev Internal check enforcing delegatecall context
  function _onlyDelegatecall() internal view {
    if (address(this) == _SELF) revert NotDelegateCall();
  }

  /// @inheritdoc IDelegatedExtension
  function handleSequenceDelegateCall(bytes32, uint256, uint256, uint256, uint256, bytes calldata data)
    external
    override
    onlyDelegatecall
  {
    // Allow delegate calls to all functions
    (bool success, bytes memory result) = address(this).delegatecall(data);
    if (!success) {
      assembly {
        revert(add(result, 32), mload(result))
      }
    }
  }
}
