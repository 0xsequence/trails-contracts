// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {ISapientCompact} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";

/// @title PayloadSwitchSapient
/// @notice An `ISapientCompact` that wraps subdigest authorisation under a kill switch.
contract PayloadSwitchSapient is ISapientCompact {
  /// @notice The caller is not the owner.
  error NotOwner();

  /// @notice Subdigest authorisation is disabled.
  error Disabled();

  /// @notice The owner of the contract.
  address public owner;

  /// @notice Whether subdigest authorisation is enabled.
  bool public enabled;

  constructor(address owner_) {
    owner = owner_;
  }

  /// @notice Sets the enabled state.
  /// @param enabled_ The new enabled state.
  function setEnabled(bool enabled_) external {
    if (msg.sender != owner) {
      revert NotOwner();
    }
    enabled = enabled_;
  }

  /// @inheritdoc ISapientCompact
  /// @notice Returns the subdigest authorisation signature.
  function recoverSapientSignatureCompact(bytes32 digest, bytes calldata) external view returns (bytes32) {
    if (!enabled) {
      revert Disabled();
    }
    return digest;
  }
}
