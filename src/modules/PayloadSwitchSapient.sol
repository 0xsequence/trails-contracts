// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

using Payload for Payload.Decoded;

/// @title PayloadSwitchSapient
/// @notice An `ISapient` that wraps subdigest authorisation under a kill switch.
contract PayloadSwitchSapient is ISapient {
  /// @notice The caller is not the owner.
  error NotOwner();

  /// @notice Subdigest authorisation is disabled.
  error Disabled();

  /// @notice The owner of the contract.
  address public owner;

  /// @notice Whether subdigest authorisation is disabled.
  bool public disabled;

  constructor(address owner_) {
    owner = owner_;
  }

  /// @notice Sets the disabled state.
  /// @param disabled_ The new disabled state.
  function setDisabled(bool disabled_) external {
    if (msg.sender != owner) {
      revert NotOwner();
    }
    disabled = disabled_;
  }

  /// @inheritdoc ISapient
  /// @notice Returns the subdigest authorisation signature.
  function recoverSapientSignature(Payload.Decoded calldata payload, bytes calldata) external view returns (bytes32) {
    if (disabled) {
      revert Disabled();
    }
    return _leafForPayload(payload);
  }

  /// @notice Returns the leaf for a payload.
  /// @dev This copies the FLAG_SIGNATURE_ANY_ADDRESS_SUBDIGEST encoding used by the wallet.
  function _leafForPayload(Payload.Decoded calldata _payload) internal view returns (bytes32) {
    bytes32 anyAddressOpHash = _payload.hashFor(address(0));
    return keccak256(abi.encodePacked("Sequence any address subdigest:\n", anyAddressOpHash));
  }
}
