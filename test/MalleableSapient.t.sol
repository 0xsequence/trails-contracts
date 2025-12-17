// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {MalleableSapient} from "src/modules/MalleableSapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {LibOptim} from "wallet-contracts-v3/utils/LibOptim.sol";

contract MalleableSapientTest is Test {
  function _randomBytes(uint256 len, bytes32 seed) private pure returns (bytes memory data) {
    data = new bytes(len);

    uint256 words = (len + 31) >> 5;
    for (uint256 i; i < words; i++) {
      bytes32 w = keccak256(abi.encodePacked(seed, i));
      assembly {
        mstore(add(add(data, 32), shl(5, i)), w)
      }
    }
  }

  function _slice(bytes memory data, uint256 start, uint256 size) private pure returns (bytes memory out) {
    out = new bytes(size);
    for (uint256 i = 0; i < size; i++) {
      out[i] = data[start + i];
    }
  }

  function _readU16(bytes memory data, uint256 index) private pure returns (uint16 v) {
    v = (uint16(uint8(data[index])) << 8) | uint16(uint8(data[index + 1]));
  }

  function _expectedImageHash(Payload.Decoded memory payload, bytes memory signature) private view returns (bytes32) {
    bytes32 root = LibOptim.fkeccak256(bytes32(payload.space), bytes32(payload.nonce));
    root = LibOptim.fkeccak256(root, bytes32(block.chainid));

    for (uint256 i = 0; i < payload.calls.length; i++) {
      Payload.Call memory call = payload.calls[i];
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
    while (rindex < signature.length) {
      uint256 tindex = uint256(uint8(signature[rindex]));
      rindex += 1;

      uint256 cindex = uint256(_readU16(signature, rindex));
      rindex += 2;

      uint256 size = uint256(_readU16(signature, rindex));
      rindex += 2;

      bytes memory segment = _slice(payload.calls[tindex].data, cindex, size);
      bytes32 sectionRoot = keccak256(abi.encode("static-section", tindex, cindex, segment));
      root = LibOptim.fkeccak256(root, sectionRoot);
    }

    return root;
  }

  function testFuzz_recoverSapientSignature_reverts_nonTransactions(uint8 kind) external {
    vm.assume(kind != Payload.KIND_TRANSACTIONS);

    MalleableSapient sapient = new MalleableSapient();

    Payload.Decoded memory payload;
    payload.kind = kind;
    payload.calls = new Payload.Call[](0);

    vm.expectRevert(MalleableSapient.NonTransactionPayload.selector);
    sapient.recoverSapientSignature(payload, "");
  }

  function testFuzz_recoverSapientSignature_emptySignature_matchesExpected(
    bytes32 seed,
    uint256 space,
    uint256 nonce,
    uint8 callCount
  ) external {
    callCount = uint8(bound(callCount, 1, 3));

    Payload.Decoded memory payload;
    payload.kind = Payload.KIND_TRANSACTIONS;
    payload.space = space;
    payload.nonce = nonce;
    payload.calls = new Payload.Call[](callCount);

    for (uint256 i = 0; i < callCount; i++) {
      payload.calls[i] = Payload.Call({
        to: address(uint160(uint256(keccak256(abi.encodePacked(seed, "to", i))))),
        value: uint256(keccak256(abi.encodePacked(seed, "value", i))),
        data: _randomBytes(bound(uint256(uint8(seed[i])), 0, 64), keccak256(abi.encodePacked(seed, "data", i))),
        gasLimit: uint256(keccak256(abi.encodePacked(seed, "gas", i))),
        delegateCall: (uint256(keccak256(abi.encodePacked(seed, "dc", i))) & 1) == 1,
        onlyFallback: (uint256(keccak256(abi.encodePacked(seed, "fb", i))) & 1) == 1,
        behaviorOnError: uint256(uint8(uint256(keccak256(abi.encodePacked(seed, "boe", i)))))
      });
    }

    MalleableSapient sapient = new MalleableSapient();

    bytes32 got = sapient.recoverSapientSignature(payload, "");
    bytes32 expected = _expectedImageHash(payload, "");
    assertEq(got, expected);
  }

  function testFuzz_recoverSapientSignature_withSections_matchesExpected(
    bytes32 seed,
    uint256 space,
    uint256 nonce,
    uint8 callCount,
    uint8 sections
  ) external {
    callCount = uint8(bound(callCount, 1, 3));
    sections = uint8(bound(sections, 1, 3));

    Payload.Decoded memory payload;
    payload.kind = Payload.KIND_TRANSACTIONS;
    payload.space = space;
    payload.nonce = nonce;
    payload.calls = new Payload.Call[](callCount);

    for (uint256 i = 0; i < callCount; i++) {
      payload.calls[i] = Payload.Call({
        to: address(uint160(uint256(keccak256(abi.encodePacked(seed, "to", i))))),
        value: uint256(keccak256(abi.encodePacked(seed, "value", i))),
        data: _randomBytes(bound(uint256(uint8(seed[i])), 1, 64), keccak256(abi.encodePacked(seed, "data", i))),
        gasLimit: uint256(keccak256(abi.encodePacked(seed, "gas", i))),
        delegateCall: (uint256(keccak256(abi.encodePacked(seed, "dc", i))) & 1) == 1,
        onlyFallback: (uint256(keccak256(abi.encodePacked(seed, "fb", i))) & 1) == 1,
        behaviorOnError: uint256(uint8(uint256(keccak256(abi.encodePacked(seed, "boe", i)))))
      });
    }

    bytes memory signature;
    for (uint256 i = 0; i < sections; i++) {
      uint8 tindex = uint8(uint256(keccak256(abi.encodePacked(seed, "t", i))) % callCount);
      uint256 dataLen = payload.calls[tindex].data.length;

      // forge-lint: disable-next-line(unsafe-typecast)
      uint16 cindex = uint16(uint256(keccak256(abi.encodePacked(seed, "c", i))) % dataLen);
      uint16 size = uint16(uint256(keccak256(abi.encodePacked(seed, "s", i))) % (dataLen - cindex + 1));

      signature = bytes.concat(signature, abi.encodePacked(tindex, cindex, size));
    }

    MalleableSapient sapient = new MalleableSapient();

    bytes32 got = sapient.recoverSapientSignature(payload, signature);
    bytes32 expected = _expectedImageHash(payload, signature);
    assertEq(got, expected);
  }
}
