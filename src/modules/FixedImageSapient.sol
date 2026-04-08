// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {ISapientCompact} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";

/// @title FixedImageSapient
/// @notice An `ISapientCompact` implementation that always returns an owner-configurable `imageHash` for any payload.
contract FixedImageSapient is ISapientCompact {
  /// @notice The caller is not the owner.
  error NotOwner();

  /// @notice The owner of the contract.
  address public owner;

  /// @notice The sapient image hash returned by `recoverSapientSignatureCompact`.
  bytes32 internal imageHash;

  constructor(address owner_) {
    owner = owner_;
  }

  /// @notice Sets the image hash returned by recovery.
  /// @param imageHash_ The new image hash.
  function setImageHash(bytes32 imageHash_) external {
    if (msg.sender != owner) {
      revert NotOwner();
    }
    imageHash = imageHash_;
  }

  /// @inheritdoc ISapientCompact
  function recoverSapientSignatureCompact(bytes32, bytes calldata) external view returns (bytes32) {
    return imageHash;
  }
}
