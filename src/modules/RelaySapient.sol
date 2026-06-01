// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title RelaySapient
/// @notice ISapient that validates Relay bridge calls via the solver's ECDSA attestation.
/// @dev The attestation is fetched from `GET /requests/{requestId}/signature/v2` and
///      verified against the known `relaySolver` address. The message format matches
///      LiFi's RelayFacet `onlyValidQuote` modifier exactly.
///
///      The returned imageHash is FIXED for a given set of PDA rules (destChainId,
///      receiver, receivingAssetId) so the PDA wallet address remains stable across deposits.
///      Per-execution data (requestId, attestation) is validated at runtime but does not
///      affect the imageHash.
contract RelaySapient is ISapient {
  using ECDSA for bytes32;
  using MessageHashUtils for bytes32;

  address public immutable relaySolver;

  error NonTransactionPayload();
  error InvalidRelaySolver(address recovered);

  constructor(address _relaySolver) {
    relaySolver = _relaySolver;
  }

  /// @inheritdoc ISapient
  /// @dev `signature` is ABI-encoded as:
  ///   (bytes32 requestId, address pdaAddress, address sendingAssetId,
  ///    uint256 destinationChainId, address receiver, bytes32 receivingAssetId,
  ///    bytes attestation)
  ///
  ///   The attestation message is:
  ///   ethSignedMessageHash(keccak256(abi.encodePacked(
  ///     requestId, block.chainid, bytes32(pdaAddress), bytes32(sendingAssetId),
  ///     destinationChainId, bytes32(receiver), receivingAssetId
  ///   )))
  function recoverSapientSignature(
    Payload.Decoded calldata payload,
    bytes calldata signature
  ) external view returns (bytes32) {
    if (payload.kind != Payload.KIND_TRANSACTIONS) {
      revert NonTransactionPayload();
    }

    (
      bytes32 requestId,
      address pdaAddress,
      address sendingAssetId,
      uint256 destinationChainId,
      address receiver,
      bytes32 receivingAssetId,
      bytes memory attestation
    ) = abi.decode(signature, (bytes32, address, address, uint256, address, bytes32, bytes));

    bytes32 message = keccak256(
      abi.encodePacked(
        requestId,
        block.chainid,
        bytes32(uint256(uint160(pdaAddress))),
        bytes32(uint256(uint160(sendingAssetId))),
        destinationChainId,
        bytes32(uint256(uint160(receiver))),
        receivingAssetId
      )
    ).toEthSignedMessageHash();

    address signer = message.recover(attestation);
    if (signer != relaySolver) {
      revert InvalidRelaySolver(signer);
    }

    return _imageHash(destinationChainId, receiver, receivingAssetId);
  }

  /// @notice Computes the fixed imageHash for a set of PDA rules.
  /// @dev This is the value that goes into the WalletConfigTreeSapientSignerLeaf
  ///      at PDA creation time.
  function imageHash(
    uint256 destinationChainId,
    address receiver,
    bytes32 receivingAssetId
  ) external view returns (bytes32) {
    return _imageHash(destinationChainId, receiver, receivingAssetId);
  }

  function _imageHash(
    uint256 destinationChainId,
    address receiver,
    bytes32 receivingAssetId
  ) internal view returns (bytes32) {
    return keccak256(
      abi.encode("RelaySapient", relaySolver, destinationChainId, receiver, receivingAssetId)
    );
  }
}
