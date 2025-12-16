// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {LibBytes} from "wallet-contracts-v3/utils/LibBytes.sol";
import {LibOptim} from "wallet-contracts-v3/utils/LibOptim.sol";


contract MalleableSapient is ISapient {
  error NonTransactionPayload();

  using LibBytes for bytes;

  function recoverSapientSignature(Payload.Decoded calldata payload, bytes calldata signature)
    external
    view
    returns (bytes32 imageHash)
  {
    if (payload.kind != Payload.KIND_TRANSACTIONS) {
      revert NonTransactionPayload();
    }

    // Roll space and nonce
    bytes32 root = LibOptim.fkeccak256(bytes32(payload.space), bytes32(payload.nonce));

    // Roll chainId
    // TODO: This bounds the intent to a single chain,
    // do we need more flexibility?
    root = LibOptim.fkeccak256(root, bytes32(block.chainid));

    unchecked {
      // Roll all calls except their `data`
      for (uint256 i = 0; i < payload.calls.length; i++) {
        Payload.Call calldata call = payload.calls[i];
        root = LibOptim.fkeccak256(
          root,
          keccak256(
            abi.encode(
              "call", i, call.to, call.value, call.gasLimit, call.delegateCall, call.onlyFallback, call.behaviorOnError
            )
          )
        );
      }

      uint256 rindex;
      uint256 tindex;
      uint256 cindex;
      uint256 size;

      while (rindex < signature.length) {
        (tindex, rindex) = signature.readUint8(rindex);
        (cindex, rindex) = signature.readUint16(rindex);
        (size, rindex) = signature.readUint16(rindex);

        // Roll only the data defined as static, everything else is malleable
        bytes32 sectionRoot = _staticSection(tindex, cindex, payload.calls[tindex].data[cindex:cindex + size]);
        root = LibOptim.fkeccak256(root, sectionRoot);
      }

      return root;
    }
  }

  function _staticSection(uint256 _tindex, uint256 _cindex, bytes calldata _data) internal pure returns (bytes32) {
    return keccak256(abi.encode("static-section", _tindex, _cindex, _data));
  }
}
