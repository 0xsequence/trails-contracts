// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

library PackedPayload {
  function packCalls(Payload.Call[] memory calls) internal pure returns (bytes memory packed) {
    require(calls.length > 0, "calls-empty");
    require(calls.length <= type(uint8).max, "calls-too-many");

    // Global flag:
    // - bit0 set => space = 0 (no space encoded)
    // - nonceSize = 0 (bits 1..3)
    // - bit4 set if single call (no numCalls encoded)
    uint8 globalFlag = 0x01;

    if (calls.length == 1) {
      globalFlag |= 0x10;
      packed = abi.encodePacked(globalFlag);
    } else {
      packed = abi.encodePacked(globalFlag, uint8(calls.length));
    }

    for (uint256 i = 0; i < calls.length; i++) {
      packed = bytes.concat(packed, _packCall(calls[i]));
    }
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

