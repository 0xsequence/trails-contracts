// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

/// @title IStargatePool
/// @notice Minimal interface for the quoteOFT view function on Stargate pools.
interface IStargatePool {
  struct SendParam {
    uint32 dstEid;
    bytes32 to;
    uint256 amountLD;
    uint256 minAmountLD;
    bytes extraOptions;
    bytes composeMsg;
    bytes oftCmd;
  }

  struct OFTLimit {
    uint256 minAmountLD;
    uint256 maxAmountLD;
  }

  struct OFTFeeDetail {
    int256 feeAmountLD;
    string description;
  }

  struct OFTReceipt {
    uint256 amountSentLD;
    uint256 amountReceivedLD;
  }

  function quoteOFT(SendParam calldata _sendParam)
    external
    view
    returns (OFTLimit memory limit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory receipt);
}

/// @title LzOftSapient
/// @notice ISapient that validates LayerZero OFT/Stargate send() calls by:
///         1. Verifying dstEid and recipient match the PDA's fixed rules
///         2. Calling quoteOFT on the pool to get amountReceivedLD
///         3. Verifying minAmountLD >= amountReceivedLD from the live on-chain quote
/// @dev The quoteOFT call reads the same pool state in the same block as the
///      subsequent send(), so the check is against live pool conditions.
///      Scoped to single-hop direct sends only (no compose/two-hop).
contract LzOftSapient is ISapient {
  // send(SendParam,MessagingFee,address)
  bytes4 private constant SEND_SELECTOR = 0xc7c7f5b3;

  address public immutable pool;

  error NonTransactionPayload();
  error InvalidSelector(bytes4 got);
  error InvalidDstEid(uint32 got, uint32 expected);
  error InvalidRecipient(bytes32 got, bytes32 expected);
  error MinAmountTooLow(uint256 minAmountLD, uint256 amountReceivedLD);

  constructor(address _pool) {
    pool = _pool;
  }

  /// @inheritdoc ISapient
  /// @dev `signature` is ABI-encoded as:
  ///   (uint8 callIndex, uint32 dstEid, bytes32 recipient)
  ///
  ///   callIndex identifies which call in payload.calls is the send().
  ///   dstEid and recipient are the PDA's fixed rules, verified against
  ///   the decoded SendParam AND committed in the returned imageHash.
  function recoverSapientSignature(
    Payload.Decoded calldata payload,
    bytes calldata signature
  ) external view returns (bytes32) {
    if (payload.kind != Payload.KIND_TRANSACTIONS) {
      revert NonTransactionPayload();
    }

    (uint8 callIndex, uint32 dstEid, bytes32 recipient) =
      abi.decode(signature, (uint8, uint32, bytes32));

    Payload.Call calldata call = payload.calls[callIndex];

    bytes4 selector = bytes4(call.data[:4]);
    if (selector != SEND_SELECTOR) {
      revert InvalidSelector(selector);
    }

    // Decode send(SendParam, MessagingFee, address)
    (IStargatePool.SendParam memory sp,,) = abi.decode(
      call.data[4:],
      (IStargatePool.SendParam, IStargatePool.OFTLimit, address)
    );

    if (sp.dstEid != dstEid) {
      revert InvalidDstEid(sp.dstEid, dstEid);
    }
    if (sp.to != recipient) {
      revert InvalidRecipient(sp.to, recipient);
    }

    // Re-run quoteOFT to get the live amountReceivedLD from the pool
    IStargatePool.SendParam memory quoteSp = IStargatePool.SendParam({
      dstEid: sp.dstEid,
      to: sp.to,
      amountLD: sp.amountLD,
      minAmountLD: 0,
      extraOptions: sp.extraOptions,
      composeMsg: sp.composeMsg,
      oftCmd: sp.oftCmd
    });

    (,, IStargatePool.OFTReceipt memory receipt) = IStargatePool(pool).quoteOFT(quoteSp);

    if (sp.minAmountLD < receipt.amountReceivedLD) {
      revert MinAmountTooLow(sp.minAmountLD, receipt.amountReceivedLD);
    }

    return _imageHash(dstEid, recipient);
  }

  /// @notice Computes the fixed imageHash for a set of PDA rules.
  function imageHash(uint32 dstEid, bytes32 recipient) external view returns (bytes32) {
    return _imageHash(dstEid, recipient);
  }

  function _imageHash(uint32 dstEid, bytes32 recipient) internal view returns (bytes32) {
    return keccak256(abi.encode("LzOftSapient", pool, dstEid, recipient));
  }
}
