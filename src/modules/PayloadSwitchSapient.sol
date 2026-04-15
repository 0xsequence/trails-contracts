// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

using Payload for Payload.Decoded;

/// @title PayloadSwitchSapient
/// @notice An `ISapient` that wraps subdigest authorisation under a pause switch.
contract PayloadSwitchSapient is ISapient, Ownable {
  /// @notice The zero address was provided where an operator address is required.
  error ZeroAddress();
  /// @notice The caller is neither the owner nor a pause operator.
  error UnauthorizedPauser(address account);
  /// @notice Subdigest authorisation is paused.
  error EnforcedPause();
  /// @notice Subdigest authorisation is not paused.
  error ExpectedPause();

  /// @notice Returns whether `account` is allowed to pause.
  mapping(address => bool) public isOperator;
  /// @notice Returns whether subdigest authorisation is paused.
  bool public paused;

  /// @notice Emitted when `account` pauses the contract.
  event Paused(address indexed account);
  /// @notice Emitted when `account` unpauses the contract.
  event Unpaused(address indexed account);
  /// @notice Emitted when an operator permission is updated.
  event OperatorSet(address indexed operator, bool allowed);

  constructor(address owner_, address[] memory initialOperators) Ownable(owner_) {
    for (uint256 i; i < initialOperators.length; i++) {
      address operator = initialOperators[i];
      if (operator == address(0)) {
        revert ZeroAddress();
      }

      isOperator[operator] = true;
    }
  }

  /// @notice Pauses subdigest authorisation.
  /// @dev Callable by the owner or an approved operator.
  function pause() external {
    if (paused) {
      revert EnforcedPause();
    }

    if (msg.sender != owner() && !isOperator[msg.sender]) {
      revert UnauthorizedPauser(msg.sender);
    }

    paused = true;
    emit Paused(msg.sender);
  }

  /// @notice Unpauses subdigest authorisation.
  /// @dev Callable only by the owner.
  function unpause() external onlyOwner {
    if (!paused) {
      revert ExpectedPause();
    }

    paused = false;
    emit Unpaused(msg.sender);
  }

  /// @notice Updates whether `operator` is allowed to pause.
  function setOperator(address operator, bool allowed) external onlyOwner {
    if (operator == address(0)) {
      revert ZeroAddress();
    }

    isOperator[operator] = allowed;
    emit OperatorSet(operator, allowed);
  }

  /// @inheritdoc ISapient
  /// @notice Returns the subdigest authorisation signature.
  function recoverSapientSignature(Payload.Decoded calldata payload, bytes calldata) external view returns (bytes32) {
    if (paused) {
      revert EnforcedPause();
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
