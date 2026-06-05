// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

/// @title OIFSapient
/// @notice ISapient that validates OIF quote attestations via EIP-712 ECDSA verification.
/// @dev Supports multi-output orders. Token and recipient fields use bytes32 to match
///      the MandateOutput format in OIF StandardOrders and support non-EVM identifiers.
contract OIFSapient is ISapient {
  using ECDSA for bytes32;

  address public immutable trustedSigner;

  error NonTransactionPayload();
  error InvalidSigner(address recovered);
  error AttestationExpired();

  bytes32 public constant QUOTE_ATTESTATION_TYPEHASH = keccak256(
    "QuoteAttestation(uint256 inputChainId,bytes32 inputToken,uint256 inputAmount,OutputCommitment[] outputs,uint256 validUntil)OutputCommitment(uint256 chainId,bytes32 token,uint256 amount,bytes32 recipient)"
  );

  bytes32 public constant OUTPUT_COMMITMENT_TYPEHASH = keccak256(
    "OutputCommitment(uint256 chainId,bytes32 token,uint256 amount,bytes32 recipient)"
  );

  bytes32 private constant DOMAIN_TYPEHASH = keccak256(
    "EIP712Domain(string name,string version,uint256 chainId)"
  );
  bytes32 private constant DOMAIN_NAME_HASH = keccak256("OIF Quote Attestation");
  bytes32 private constant DOMAIN_VERSION_HASH = keccak256("1");

  struct OutputCommitment {
    uint256 chainId;
    bytes32 token;
    uint256 amount;
    bytes32 recipient;
  }

  constructor(address _trustedSigner) {
    trustedSigner = _trustedSigner;
  }

  /// @inheritdoc ISapient
  /// @dev `signature` is ABI-encoded as:
  ///   (uint256 inputChainId, bytes32 inputToken, uint256 inputAmount,
  ///    OutputCommitment[] outputs, uint256 validUntil, bytes attestation)
  function recoverSapientSignature(
    Payload.Decoded calldata payload,
    bytes calldata signature
  ) external view returns (bytes32) {
    if (payload.kind != Payload.KIND_TRANSACTIONS) {
      revert NonTransactionPayload();
    }

    (
      uint256 inputChainId,
      bytes32 inputToken,
      uint256 inputAmount,
      OutputCommitment[] memory outputs,
      uint256 validUntil,
      bytes memory attestation
    ) = abi.decode(signature, (uint256, bytes32, uint256, OutputCommitment[], uint256, bytes));

    if (block.timestamp > validUntil) {
      revert AttestationExpired();
    }

    // Hash each output commitment
    bytes32[] memory outputHashes = new bytes32[](outputs.length);
    for (uint256 i = 0; i < outputs.length; i++) {
      outputHashes[i] = keccak256(
        abi.encode(
          OUTPUT_COMMITMENT_TYPEHASH,
          outputs[i].chainId,
          outputs[i].token,
          outputs[i].amount,
          outputs[i].recipient
        )
      );
    }

    bytes32 domainSeparator = keccak256(
      abi.encode(DOMAIN_TYPEHASH, DOMAIN_NAME_HASH, DOMAIN_VERSION_HASH, inputChainId)
    );

    bytes32 structHash = keccak256(
      abi.encode(
        QUOTE_ATTESTATION_TYPEHASH,
        inputChainId,
        inputToken,
        inputAmount,
        keccak256(abi.encodePacked(outputHashes)),
        validUntil
      )
    );

    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    address recovered = digest.recover(attestation);

    if (recovered != trustedSigner) {
      revert InvalidSigner(recovered);
    }

    return _imageHash(inputChainId, inputToken, outputs);
  }

  /// @notice Computes the fixed imageHash for a set of PDA route parameters.
  /// @dev Commits to static route identity (tokens, chains, recipients, signer).
  ///      Amounts and expiry are excluded - validated by ecrecover at runtime.
  function imageHash(
    uint256 inputChainId,
    bytes32 inputToken,
    OutputCommitment[] calldata outputs
  ) external view returns (bytes32) {
    return _imageHash(inputChainId, inputToken, outputs);
  }

  function _imageHash(
    uint256 inputChainId,
    bytes32 inputToken,
    OutputCommitment[] memory outputs
  ) internal view returns (bytes32) {
    // Hash output route identities (chainId, token, recipient) without amounts
    bytes32[] memory outputIdentities = new bytes32[](outputs.length);
    for (uint256 i = 0; i < outputs.length; i++) {
      outputIdentities[i] = keccak256(
        abi.encode(outputs[i].chainId, outputs[i].token, outputs[i].recipient)
      );
    }

    return keccak256(
      abi.encode(
        "OIFSapient",
        trustedSigner,
        inputChainId,
        inputToken,
        keccak256(abi.encodePacked(outputIdentities))
      )
    );
  }
}
