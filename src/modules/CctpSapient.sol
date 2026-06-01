// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

/// @title CctpSapient
/// @notice ISapient that validates CCTP depositForBurn calls by ABI-decoding and
///         checking destination parameters against the PDA's fixed rules.
/// @dev CCTP is Category A: all parameters are on-chain verifiable. The sapient
///      decodes the depositForBurn calldata from the payload and verifies that
///      destinationDomain, mintRecipient, and burnToken match the immutable PDA rules.
///      Amount is malleable (hydrated from balance at runtime).
///
///      The returned imageHash is FIXED for a given set of PDA rules so the wallet
///      address remains stable across deposits.
contract CctpSapient is ISapient {
  address public immutable tokenMessenger;

  // depositForBurn(uint256,uint32,bytes32,address,bytes32,uint256,uint32)
  bytes4 private constant DEPOSIT_FOR_BURN_SELECTOR = 0x2eca2558;

  error NonTransactionPayload();
  error NoDepositForBurnCall();
  error InvalidDestinationDomain(uint32 got, uint32 expected);
  error InvalidMintRecipient(bytes32 got, bytes32 expected);
  error InvalidBurnToken(address got, address expected);

  constructor(address _tokenMessenger) {
    tokenMessenger = _tokenMessenger;
  }

  /// @inheritdoc ISapient
  /// @dev `signature` is ABI-encoded as:
  ///   (uint8 callIndex, uint32 destinationDomain, bytes32 mintRecipient, address burnToken)
  ///
  ///   callIndex identifies which call in payload.calls is the depositForBurn.
  ///   The sapient decodes the call's data and verifies the fixed params match.
  function recoverSapientSignature(
    Payload.Decoded calldata payload,
    bytes calldata signature
  ) external view returns (bytes32) {
    if (payload.kind != Payload.KIND_TRANSACTIONS) {
      revert NonTransactionPayload();
    }

    (
      uint8 callIndex,
      uint32 destinationDomain,
      bytes32 mintRecipient,
      address burnToken
    ) = abi.decode(signature, (uint8, uint32, bytes32, address));

    Payload.Call calldata call = payload.calls[callIndex];

    bytes4 selector = bytes4(call.data[:4]);
    if (selector != DEPOSIT_FOR_BURN_SELECTOR) {
      revert NoDepositForBurnCall();
    }

    // depositForBurn(uint256 amount, uint32 destinationDomain, bytes32 mintRecipient,
    //                address burnToken, bytes32 destinationCaller, uint256 maxFee,
    //                uint32 minFinalityThreshold)
    (
      , // uint256 amount - malleable (hydrated from balance)
      uint32 actualDestDomain,
      bytes32 actualMintRecipient,
      address actualBurnToken,
      , // bytes32 destinationCaller
      , // uint256 maxFee
        // uint32 minFinalityThreshold
    ) = abi.decode(call.data[4:], (uint256, uint32, bytes32, address, bytes32, uint256, uint32));

    if (actualDestDomain != destinationDomain) {
      revert InvalidDestinationDomain(actualDestDomain, destinationDomain);
    }
    if (actualMintRecipient != mintRecipient) {
      revert InvalidMintRecipient(actualMintRecipient, mintRecipient);
    }
    if (actualBurnToken != burnToken) {
      revert InvalidBurnToken(actualBurnToken, burnToken);
    }

    return _imageHash(destinationDomain, mintRecipient, burnToken);
  }

  /// @notice Computes the fixed imageHash for a set of PDA rules.
  function imageHash(
    uint32 destinationDomain,
    bytes32 mintRecipient,
    address burnToken
  ) external view returns (bytes32) {
    return _imageHash(destinationDomain, mintRecipient, burnToken);
  }

  function _imageHash(
    uint32 destinationDomain,
    bytes32 mintRecipient,
    address burnToken
  ) internal view returns (bytes32) {
    return keccak256(
      abi.encode("CctpSapient", tokenMessenger, destinationDomain, mintRecipient, burnToken)
    );
  }
}
