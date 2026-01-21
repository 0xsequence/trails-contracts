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
    if (payload.noChainId) {
      root = LibOptim.fkeccak256(root, bytes32(0));
    } else {
      root = LibOptim.fkeccak256(root, bytes32(block.chainid));
    }

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

      // Top bit of tindex indicates whether this is a "repeat-section" or a "static-section"
      bool repeatSection = (tindex & 0x80) != 0;
      tindex = tindex & 0x7F;

      if (repeatSection) {
        uint256 tindex2 = uint256(uint8(signature[rindex]));
        rindex += 1;

        uint256 cindex2 = uint256(_readU16(signature, rindex));
        rindex += 2;

        bytes32 sectionRoot = keccak256(abi.encode("repeat-section", tindex, cindex, size, tindex2, cindex2));
        root = LibOptim.fkeccak256(root, sectionRoot);
      } else {
        bytes memory segment = _slice(payload.calls[tindex].data, cindex, size);
        bytes32 sectionRoot = keccak256(abi.encode("static-section", tindex, cindex, segment));
        root = LibOptim.fkeccak256(root, sectionRoot);
      }
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

  struct SignatureParts {
    uint8 tindex;
    uint16 cindex;
    uint16 size;
    uint8 tindex2;
    uint16 cindex2;
  }

  function testFuzz_recoverSapientSignature_withSections_matchesExpected(
    bytes32 seed,
    uint256 space,
    uint256 nonce,
    uint8 callCount,
    uint8 sections
  ) external {
    callCount = uint8(bound(callCount, 1, 10));
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

    // Prevent overlap by requring separate tindex for each repeat section
    uint256[] memory tindexWithRepeat = new uint256[](sections * 2);

    SignatureParts memory parts;
    bytes memory signature;
    for (uint256 i = 0; i < sections; i++) {
      parts.tindex = uint8(uint256(keccak256(abi.encodePacked(seed, "t", i))) % callCount);
      uint256 dataLen = payload.calls[parts.tindex].data.length;

      // forge-lint: disable-next-line(unsafe-typecast)
      parts.cindex = uint16(uint256(keccak256(abi.encodePacked(seed, "c", i))) % dataLen);
      parts.size = uint16(uint256(keccak256(abi.encodePacked(seed, "s", i))) % (dataLen - parts.cindex + 1));

      bool isRepeatSection = (uint256(keccak256(abi.encodePacked(seed, "rs", i))) & 1) == 1;
      if (isRepeatSection) {
        parts.tindex2 = uint8(uint256(keccak256(abi.encodePacked(seed, "t2", i))) % callCount);
        // Prevent collision by checking tindex is not repeated
        vm.assume(parts.tindex != parts.tindex2);
        for (uint256 j = 0; j < i * 2; j++) {
          vm.assume(parts.tindex != tindexWithRepeat[j]);
          vm.assume(parts.tindex2 != tindexWithRepeat[j]);
        }
        tindexWithRepeat[i] = parts.tindex;
        tindexWithRepeat[i + 1] = parts.tindex2;

        uint256 dataLen2 = payload.calls[parts.tindex2].data.length;
        // forge-lint: disable-next-line(unsafe-typecast)
        parts.cindex2 = uint16(uint256(keccak256(abi.encodePacked(seed, "c2", i))) % dataLen2);
        uint16 size2 = uint16(uint256(keccak256(abi.encodePacked(seed, "s2", i))) % (dataLen2 - parts.cindex2 + 1));
        if (parts.size > size2) {
          // Use the smaller size
          parts.size = size2;
        }
        uint8 flaggedTindex = parts.tindex | 0x80;
        signature = bytes.concat(
          signature, abi.encodePacked(flaggedTindex, parts.cindex, parts.size, parts.tindex2, parts.cindex2)
        );

        // Ensure the section is repeated
        bytes memory repeatSection = _slice(payload.calls[parts.tindex].data, parts.cindex, parts.size);
        bytes memory sectionA = _slice(payload.calls[parts.tindex2].data, 0, parts.cindex2);
        bytes memory sectionB =
          _slice(payload.calls[parts.tindex2].data, parts.cindex2 + parts.size, dataLen2 - parts.cindex2 - parts.size);
        payload.calls[parts.tindex2].data = bytes.concat(sectionA, repeatSection, sectionB);
      } else {
        signature = bytes.concat(signature, abi.encodePacked(parts.tindex, parts.cindex, parts.size));
      }
    }

    MalleableSapient sapient = new MalleableSapient();

    bytes32 got = sapient.recoverSapientSignature(payload, signature);
    bytes32 expected = _expectedImageHash(payload, signature);
    assertEq(got, expected);
  }

  struct InvalidRepeatSectionParts {
    uint8 tindex;
    uint16 cindex;
    uint16 size;
    uint8 tindex2;
    uint16 cindex2;
  }

  function test_recoverSapientSignature_invalidRepeatSection_reverts(
    bytes32 seed,
    uint256 space,
    uint256 nonce,
    uint8 callCount,
    uint8 sections
  ) external {
    callCount = uint8(bound(callCount, 1, 10));
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

    InvalidRepeatSectionParts memory invalidParts;
    SignatureParts memory parts;
    bytes memory signature;
    for (uint256 i = 0; i < sections; i++) {
      parts.tindex = uint8(uint256(keccak256(abi.encodePacked(seed, "t", i))) % callCount);
      uint256 dataLen = payload.calls[parts.tindex].data.length;

      // forge-lint: disable-next-line(unsafe-typecast)
      parts.cindex = uint16(uint256(keccak256(abi.encodePacked(seed, "c", i))) % dataLen);
      parts.size = uint16(uint256(keccak256(abi.encodePacked(seed, "s", i))) % (dataLen - parts.cindex + 1));

      parts.tindex2 = uint8(uint256(keccak256(abi.encodePacked(seed, "t2", i))) % callCount);
      uint256 dataLen2 = payload.calls[parts.tindex2].data.length;
      // forge-lint: disable-next-line(unsafe-typecast)
      parts.cindex2 = uint16(uint256(keccak256(abi.encodePacked(seed, "c2", i))) % dataLen2);
      uint16 size2 = uint16(uint256(keccak256(abi.encodePacked(seed, "s2", i))) % (dataLen2 - parts.cindex2 + 1));
      if (parts.size > size2) {
        // Use the smaller size
        parts.size = size2;
      }
      uint8 flaggedTindex = parts.tindex | 0x80;
      signature = bytes.concat(
        signature, abi.encodePacked(flaggedTindex, parts.cindex, parts.size, parts.tindex2, parts.cindex2)
      );

      if (invalidParts.size == 0) {
        // Check if the section is a repeat
        bytes memory section = _slice(payload.calls[parts.tindex].data, parts.cindex, parts.size);
        bytes memory section2 = _slice(payload.calls[parts.tindex2].data, parts.cindex2, parts.size);
        if (keccak256(section) != keccak256(section2)) {
          invalidParts = InvalidRepeatSectionParts({
            tindex: parts.tindex, cindex: parts.cindex, size: parts.size, tindex2: parts.tindex2, cindex2: parts.cindex2
          });
        }
      }
    }

    // At least one of the repeat sections must be invalid
    vm.assume(invalidParts.size != 0);

    MalleableSapient sapient = new MalleableSapient();

    vm.expectRevert(
      abi.encodeWithSelector(
        MalleableSapient.InvalidRepeatSection.selector,
        invalidParts.tindex,
        invalidParts.cindex,
        invalidParts.size,
        invalidParts.tindex2,
        invalidParts.cindex2
      )
    );
    sapient.recoverSapientSignature(payload, signature);
  }

  function test_recoverSapientSignature_chainId_included() external {
    MalleableSapient sapient = new MalleableSapient();

    Payload.Decoded memory payload;
    payload.kind = Payload.KIND_TRANSACTIONS;
    payload.space = 1;
    payload.nonce = 2;
    payload.noChainId = false;
    payload.calls = new Payload.Call[](1);
    payload.calls[0] = Payload.Call({
      to: address(0x1234), value: 0, data: "", gasLimit: 0, delegateCall: false, onlyFallback: false, behaviorOnError: 0
    });

    bytes32 hash = sapient.recoverSapientSignature(payload, "");
    bytes32 expected = _expectedImageHash(payload, "");

    // Hash should match expected (which includes block.chainid)
    assertEq(hash, expected);

    // Verify the hash includes chain ID by checking it's different from noChainId version
    payload.noChainId = true;
    bytes32 hashNoChainId = sapient.recoverSapientSignature(payload, "");
    assertNotEq(hash, hashNoChainId);
  }

  function test_recoverSapientSignature_noChainId_zeroUsed() external {
    MalleableSapient sapient = new MalleableSapient();

    Payload.Decoded memory payload;
    payload.kind = Payload.KIND_TRANSACTIONS;
    payload.space = 1;
    payload.nonce = 2;
    payload.noChainId = true;
    payload.calls = new Payload.Call[](1);
    payload.calls[0] = Payload.Call({
      to: address(0x1234), value: 0, data: "", gasLimit: 0, delegateCall: false, onlyFallback: false, behaviorOnError: 0
    });

    bytes32 hash = sapient.recoverSapientSignature(payload, "");
    bytes32 expected = _expectedImageHash(payload, "");

    // Hash should match expected (which uses bytes32(0) for chain ID)
    assertEq(hash, expected);

    // Verify the hash uses zero by manually computing with zero
    bytes32 root = LibOptim.fkeccak256(bytes32(payload.space), bytes32(payload.nonce));
    root = LibOptim.fkeccak256(root, bytes32(0)); // Should use zero, not block.chainid
    root = LibOptim.fkeccak256(
      root,
      keccak256(
        abi.encode(
          "call",
          uint256(0),
          payload.calls[0].to,
          payload.calls[0].value,
          payload.calls[0].gasLimit,
          payload.calls[0].delegateCall,
          payload.calls[0].onlyFallback,
          payload.calls[0].behaviorOnError
        )
      )
    );
    assertEq(hash, root);
  }

  function testFuzz_recoverSapientSignature_chainId_vs_noChainId(
    bytes32 seed,
    uint256 space,
    uint256 nonce,
    uint8 callCount
  ) external {
    callCount = uint8(bound(callCount, 1, 3));

    Payload.Decoded memory payloadWithChainId;
    payloadWithChainId.kind = Payload.KIND_TRANSACTIONS;
    payloadWithChainId.space = space;
    payloadWithChainId.nonce = nonce;
    payloadWithChainId.noChainId = false;
    payloadWithChainId.calls = new Payload.Call[](callCount);

    Payload.Decoded memory payloadNoChainId;
    payloadNoChainId.kind = Payload.KIND_TRANSACTIONS;
    payloadNoChainId.space = space;
    payloadNoChainId.nonce = nonce;
    payloadNoChainId.noChainId = true;
    payloadNoChainId.calls = new Payload.Call[](callCount);

    for (uint256 i = 0; i < callCount; i++) {
      Payload.Call memory call = Payload.Call({
        to: address(uint160(uint256(keccak256(abi.encodePacked(seed, "to", i))))),
        value: uint256(keccak256(abi.encodePacked(seed, "value", i))),
        data: _randomBytes(bound(uint256(uint8(seed[i])), 0, 64), keccak256(abi.encodePacked(seed, "data", i))),
        gasLimit: uint256(keccak256(abi.encodePacked(seed, "gas", i))),
        delegateCall: (uint256(keccak256(abi.encodePacked(seed, "dc", i))) & 1) == 1,
        onlyFallback: (uint256(keccak256(abi.encodePacked(seed, "fb", i))) & 1) == 1,
        behaviorOnError: uint256(uint8(uint256(keccak256(abi.encodePacked(seed, "boe", i)))))
      });
      payloadWithChainId.calls[i] = call;
      payloadNoChainId.calls[i] = call;
    }

    MalleableSapient sapient = new MalleableSapient();

    bytes32 hashWithChainId = sapient.recoverSapientSignature(payloadWithChainId, "");
    bytes32 hashNoChainId = sapient.recoverSapientSignature(payloadNoChainId, "");

    // Hashes should be different because one includes chain ID and the other uses zero
    assertNotEq(hashWithChainId, hashNoChainId);

    // Verify they match expected values
    assertEq(hashWithChainId, _expectedImageHash(payloadWithChainId, ""));
    assertEq(hashNoChainId, _expectedImageHash(payloadNoChainId, ""));
  }
}
