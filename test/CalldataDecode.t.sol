// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import "forge-std/Test.sol";

import {CalldataDecode} from "src/utils/CalldataDecode.sol";

contract CalldataDecodeHarness {
  function decodeBytesBytes(bytes calldata data) external pure returns (bytes memory a, bytes memory b) {
    (bytes calldata ac, bytes calldata bc) = CalldataDecode.decodeBytesBytes(data);
    return (ac, bc);
  }
}

contract CalldataDecodeTest is Test {
  CalldataDecodeHarness private harness = new CalldataDecodeHarness();

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

  function test_decodeBytesBytes_roundTrip() public view {
    bytes memory a = hex"";
    bytes memory b = hex"010203";

    (bytes memory gotA, bytes memory gotB) = harness.decodeBytesBytes(abi.encode(a, b));
    assertEq(gotA, a);
    assertEq(gotB, b);
  }

  function test_decodeBytesBytes_reverts_short() public {
    vm.expectRevert();
    harness.decodeBytesBytes(new bytes(0));

    vm.expectRevert();
    harness.decodeBytesBytes(new bytes(63));
  }

  function test_decodeBytesBytes_reverts_misalignedOffset() public {
    bytes memory data = abi.encode(bytes("a"), bytes("b"));
    assembly {
      // First head word (offset to first bytes) starts at `data + 32`.
      mstore(add(data, 32), 65)
    }

    vm.expectRevert();
    harness.decodeBytesBytes(data);
  }

  function test_decodeBytesBytes_reverts_lengthOutOfBounds() public {
    bytes memory data = abi.encode(bytes("a"), bytes("b"));
    assembly {
      // aRel is 64, so the length word for `a` starts at `data + 32 + 64`.
      mstore(add(data, 96), 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff)
    }

    vm.expectRevert();
    harness.decodeBytesBytes(data);
  }

  function test_decodeBytesBytes_reverts_offsetsTooSmall() public {
    bytes memory data = new bytes(64);
    assembly {
      mstore(add(data, 32), 32) // aRel (word-aligned, but < 64)
      mstore(add(data, 64), 64) // bRel
    }

    vm.expectRevert();
    harness.decodeBytesBytes(data);
  }

  function test_decodeBytesBytes_reverts_aDataRel_outOfBounds() public {
    bytes memory data = new bytes(64);
    assembly {
      mstore(add(data, 32), 64) // aRel
      mstore(add(data, 64), 64) // bRel
    }

    vm.expectRevert();
    harness.decodeBytesBytes(data);
  }

  function test_decodeBytesBytes_reverts_aDataRel_overflow() public {
    bytes memory data = new bytes(64);
    uint256 huge = type(uint256).max - 31; // 2^256 - 32, word-aligned and >= 64
    assembly {
      mstore(add(data, 32), huge) // aRel
      mstore(add(data, 64), 64) // bRel
    }

    vm.expectRevert();
    harness.decodeBytesBytes(data);
  }

  function test_decodeBytesBytes_reverts_aEndRel_outOfBounds() public {
    bytes memory data = new bytes(96);
    assembly {
      mstore(add(data, 32), 64) // aRel
      mstore(add(data, 64), 64) // bRel
      mstore(add(data, 96), 1) // aLen (aDataRel == len, so aLen must be 0 to pass; 1 forces aEndRel > len)
    }

    vm.expectRevert();
    harness.decodeBytesBytes(data);
  }

  function test_decodeBytesBytes_reverts_bDataRel_outOfBounds() public {
    bytes memory data = new bytes(96);
    assembly {
      mstore(add(data, 32), 64) // aRel
      mstore(add(data, 64), 96) // bRel (bDataRel = 128 > len)
      mstore(add(data, 96), 0) // aLen (so aEndRel == aDataRel == len)
    }

    vm.expectRevert();
    harness.decodeBytesBytes(data);
  }

  function test_decodeBytesBytes_reverts_bEndRel_outOfBounds() public {
    bytes memory data = new bytes(128);
    assembly {
      mstore(add(data, 32), 64) // aRel
      mstore(add(data, 64), 96) // bRel (bDataRel == len)
      mstore(add(data, 96), 0) // aLen (so aEndRel == aDataRel)
      mstore(add(data, 128), 1) // bLen (so bEndRel > len)
    }

    vm.expectRevert();
    harness.decodeBytesBytes(data);
  }

  function testFuzz_decodeBytesBytes_roundTrip(bytes32 seedA, bytes32 seedB, uint256 lenA, uint256 lenB) public view {
    lenA = bound(lenA, 0, 256);
    lenB = bound(lenB, 0, 256);

    bytes memory a = _randomBytes(lenA, seedA);
    bytes memory b = _randomBytes(lenB, seedB);

    (bytes memory gotA, bytes memory gotB) = harness.decodeBytesBytes(abi.encode(a, b));
    assertEq(gotA, a);
    assertEq(gotB, b);
  }

  function testFuzz_decodeBytesBytes_roundTrip_direct(bytes memory a, bytes memory b) public view {
    vm.assume(a.length <= 1024);
    vm.assume(b.length <= 1024);

    (bytes memory gotA, bytes memory gotB) = harness.decodeBytesBytes(abi.encode(a, b));
    assertEq(gotA, a);
    assertEq(gotB, b);
  }
}
