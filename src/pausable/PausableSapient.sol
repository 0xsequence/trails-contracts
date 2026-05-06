// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Pausable} from "src/pausable/Pausable.sol";
import {ISapientCompact} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";

/// @title PausableSapient
/// @notice Compact sapient signer that returns a fixed image hash unless paused.
/// @dev Reverts with `EnforcedPause` while paused.
/// @dev Does not verify signatures; use co-signers with real verification at the nested tree level.
contract PausableSapient is ISapientCompact, Pausable {
  /// @notice Image hash returned while the signer is active.
  bytes32 public constant UNPAUSED_IMAGE_HASH = bytes32(uint256(1));

  /// @notice Initializes the pause controller.
  /// @param owner_ The owner allowed to manage operators and unpause.
  /// @param initialOperators The initial set of addresses allowed to pause.
  constructor(address owner_, address[] memory initialOperators) Pausable(owner_, initialOperators) {}

  /// @inheritdoc ISapientCompact
  function recoverSapientSignatureCompact(bytes32, bytes calldata)
    external
    view
    whenNotPaused
    returns (bytes32 imageHash)
  {
    return UNPAUSED_IMAGE_HASH;
  }
}
