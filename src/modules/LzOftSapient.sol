// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

/// @title IStargatePool
/// @notice Minimal interface for the quoteOFT view function on Stargate/OFT pools.
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
/// @notice Pool-agnostic ISapient for LayerZero OFT/Stargate send() calls.
///         The pool address is passed in the signature blob and committed in
///         the returned imageHash, so each PDA locks in its pool without
///         requiring a separate contract deployment per pool.
/// @dev Validates by:
///      1. ABI-decoding the send() calldata from the payload
///      2. Verifying dstEid, recipient, and call target (pool) match PDA rules
///      3. Calling pool.quoteOFT() to verify minAmountLD >= amountReceivedLD
contract LzOftSapient is ISapient {
  // send(SendParam,MessagingFee,address)
  bytes4 private constant SEND_SELECTOR = 0xc7c7f5b3;

  error NonTransactionPayload();
  error InvalidSelector(bytes4 got);
  error InvalidPool(address got, address expected);
  error InvalidDstEid(uint32 got, uint32 expected);
  error InvalidRecipient(bytes32 got, bytes32 expected);
  error MinAmountTooLow(uint256 minAmountLD, uint256 amountReceivedLD);

  /// @inheritdoc ISapient
  /// @dev `signature` is ABI-encoded as:
  ///   (uint8 callIndex, address pool, uint32 dstEid, bytes32 recipient)
  ///
  ///   All four fields are PDA fixed rules. The wallet config's sapient leaf
  ///   commits to `imageHash(pool, dstEid, recipient)`, so the worker cannot
  ///   substitute a different pool or destination.
  function recoverSapientSignature(
    Payload.Decoded calldata payload,
    bytes calldata signature
  ) external view returns (bytes32) {
    if (payload.kind != Payload.KIND_TRANSACTIONS) {
      revert NonTransactionPayload();
    }

    (uint8 callIndex, address pool, uint32 dstEid, bytes32 recipient) =
      abi.decode(signature, (uint8, address, uint32, bytes32));

    Payload.Call calldata call = payload.calls[callIndex];

    if (call.to != pool) {
      revert InvalidPool(call.to, pool);
    }

    bytes4 selector = bytes4(call.data[:4]);
    if (selector != SEND_SELECTOR) {
      revert InvalidSelector(selector);
    }

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

    return _imageHash(pool, dstEid, recipient);
  }

  /// @notice Computes the fixed imageHash for a set of PDA rules.
  function imageHash(address pool, uint32 dstEid, bytes32 recipient) external pure returns (bytes32) {
    return _imageHash(pool, dstEid, recipient);
  }

  function _imageHash(address pool, uint32 dstEid, bytes32 recipient) internal pure returns (bytes32) {
    return keccak256(abi.encode("LzOftSapient", pool, dstEid, recipient));
  }
}
