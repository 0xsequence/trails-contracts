// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Pausable} from "src/pausable/Pausable.sol";
import {ISapientCompact} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";

/// @title PausableSapient
/// @notice Compact sapient signer that flips between a live and paused image hash.
/// @dev Returns `bytes32(uint256(1))` while unpaused and `bytes32(0)` while paused.
contract PausableSapient is ISapientCompact, Pausable {
  /// @notice Image hash returned while the signer is active.
  bytes32 public constant UNPAUSED_IMAGE_HASH = bytes32(uint256(1));
  /// @notice Image hash returned while the signer is paused.
  bytes32 public constant PAUSED_IMAGE_HASH = bytes32(0);

  /// @notice Initializes the pause controller.
  /// @param owner_ The owner allowed to manage operators and unpause.
  /// @param initialOperators The initial set of addresses allowed to pause.
  constructor(address owner_, address[] memory initialOperators) Pausable(owner_, initialOperators) {}

  /// @inheritdoc ISapientCompact
  function recoverSapientSignatureCompact(bytes32, bytes calldata) external view returns (bytes32 imageHash) {
    return paused ? PAUSED_IMAGE_HASH : UNPAUSED_IMAGE_HASH;
  }
}
