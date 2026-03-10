// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

library PackedPayload {
  function packCalls(Payload.Call[] memory calls) internal pure returns (bytes memory packed) {
    return packCallsWithSpaceNonce(calls, 0, 0);
  }

  function packCallsWithSpaceNonce(Payload.Call[] memory calls, uint256 space, uint256 nonce)
    internal
    pure
    returns (bytes memory packed)
  {
    require(calls.length > 0, "calls-empty");
    require(calls.length <= type(uint8).max, "calls-too-many");
    require(space <= type(uint160).max, "space-too-large");
    require(nonce <= type(uint56).max, "nonce-too-large");

    // Global flag:
    // - bit0 set => space = 0 (no space encoded)
    // - bits 1..3 encode the nonce size
    // - bit4 set if single call (no numCalls encoded)
    uint8 globalFlag;
    if (space == 0) {
      globalFlag |= 0x01;
    }

    uint8 nonceSize = _nonceSize(nonce);
    globalFlag |= nonceSize << 1;

    if (calls.length == 1) {
      globalFlag |= 0x10;
    }

    packed = abi.encodePacked(globalFlag);
    if (space != 0) {
      packed = bytes.concat(packed, abi.encodePacked(bytes20(uint160(space))));
    }
    if (nonceSize != 0) {
      packed = bytes.concat(packed, _encodeUintX(nonce, nonceSize));
    }
    if (calls.length != 1) {
      packed = bytes.concat(packed, abi.encodePacked(uint8(calls.length)));
    }

    for (uint256 i = 0; i < calls.length; i++) {
      packed = bytes.concat(packed, _packCall(calls[i]));
    }
  }

  function _nonceSize(uint256 nonce) private pure returns (uint8) {
    if (nonce == 0) return 0;
    if (nonce <= type(uint8).max) return 1;
    if (nonce <= type(uint16).max) return 2;
    if (nonce <= type(uint24).max) return 3;
    if (nonce <= type(uint32).max) return 4;
    if (nonce <= type(uint40).max) return 5;
    if (nonce <= type(uint48).max) return 6;
    return 7;
  }

  function _encodeUintX(uint256 value, uint8 length) private pure returns (bytes memory out) {
    if (length == 1) return abi.encodePacked(uint8(value));
    if (length == 2) return abi.encodePacked(uint16(value));
    if (length == 3) return abi.encodePacked(uint24(value));
    if (length == 4) return abi.encodePacked(uint32(value));
    if (length == 5) return abi.encodePacked(bytes5(uint40(value)));
    if (length == 6) return abi.encodePacked(bytes6(uint48(value)));
    if (length == 7) return abi.encodePacked(bytes7(uint56(value)));
    revert("invalid-uintx-length");
  }

  function _packCall(Payload.Call memory call) private pure returns (bytes memory out) {
    // Call flags:
    // - bit0: callToSelf (unused in these tests, always 0)
    // - bit1: hasValue (always 1)
    // - bit2: hasData  (always 1)
    // - bit3: hasGas  (always 1)
    // - bit4: delegateCall
    // - bit5: onlyFallback
    // - bits6..7: behaviorOnError
    uint8 flags = 0x02 | 0x04 | 0x08;

    if (call.delegateCall) flags |= 0x10;
    if (call.onlyFallback) flags |= 0x20;
    flags |= (uint8(call.behaviorOnError) & 0x03) << 6;

    out = abi.encodePacked(flags, call.to, call.value, uint24(call.data.length), call.data, call.gasLimit);
  }
}
