// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {ReplaceBytes} from "src/utils/ReplaceBytes.sol";

contract ReplaceBytesTest is Test {
  using ReplaceBytes for bytes;

  function _replaceUint256(bytes memory data, uint256 offset, uint256 val) external pure returns (bytes memory) {
    data.replaceUint256(offset, val);
    return data;
  }

  function _replaceAddress(bytes memory data, uint256 offset, address addr) external pure returns (bytes memory) {
    data.replaceAddress(offset, addr);
    return data;
  }

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

  function _copy(bytes memory data) private pure returns (bytes memory out) {
    out = new bytes(data.length);
    for (uint256 i; i < data.length; i++) {
      out[i] = data[i];
    }
  }

  function _apply(bytes memory data, uint256 offset, bytes memory replacement) private pure {
    for (uint256 i; i < replacement.length; i++) {
      data[offset + i] = replacement[i];
    }
  }

  function test_replaceUint256_inPlace_aliasReflectsMutation() public pure {
    bytes memory data = _randomBytes(96, keccak256("seed"));
    bytes memory alias_ = data;
    bytes memory expected = _copy(data);

    uint256 offset = 17;
    uint256 val = uint256(keccak256("val"));
    data.replaceUint256(offset, val);

    _apply(expected, offset, abi.encodePacked(val));
    assertEq(alias_, expected);
    assertEq(data, expected);
  }

  function test_replaceUint256_offsets_allAlignments() public pure {
    uint256 val = 0x0123456789abcdef;

    for (uint256 offset; offset < 64; offset++) {
      bytes memory data = _randomBytes(offset + 32 + 17, bytes32(offset));
      bytes memory expected = _copy(data);

      data.replaceUint256(offset, val);
      _apply(expected, offset, abi.encodePacked(val));

      assertEq(data, expected);
    }
  }

  function test_replaceUint256_exactEndOffsets() public pure {
    uint256 val = uint256(keccak256("u256"));

    bytes memory data = _randomBytes(32, bytes32(uint256(1)));
    bytes memory expected = _copy(data);
    data.replaceUint256(0, val);
    _apply(expected, 0, abi.encodePacked(val));
    assertEq(data, expected);

    data = _randomBytes(33, bytes32(uint256(2)));
    expected = _copy(data);
    data.replaceUint256(1, val);
    _apply(expected, 1, abi.encodePacked(val));
    assertEq(data, expected);

    data = _randomBytes(64, bytes32(uint256(3)));
    expected = _copy(data);
    data.replaceUint256(32, val);
    _apply(expected, 32, abi.encodePacked(val));
    assertEq(data, expected);
  }

  function test_replaceUint256_reverts_outOfBounds() public {
    bytes memory data = new bytes(31);
    vm.expectRevert();
    this._replaceUint256(data, 0, 1);

    data = new bytes(32);
    vm.expectRevert();
    this._replaceUint256(data, 1, 1);
  }

  function test_replaceUint256_reverts_overflowEnd() public {
    bytes memory data = new bytes(64);
    vm.expectRevert();
    this._replaceUint256(data, type(uint256).max - 16, 1);
  }

  function test_replaceAddress_inPlace_aliasReflectsMutation() public pure {
    bytes memory data = _randomBytes(96, keccak256("seed2"));
    bytes memory alias_ = data;
    bytes memory expected = _copy(data);

    uint256 offset = 23;
    address addr = address(0x111122223333444455556666777788889999aAaa);
    data.replaceAddress(offset, addr);

    _apply(expected, offset, abi.encodePacked(addr));
    assertEq(alias_, expected);
    assertEq(data, expected);
  }

  function test_replaceAddress_offsets_allAlignments() public pure {
    address addr = address(0x1234567890AbcdEF1234567890aBcdef12345678);

    for (uint256 offset; offset < 64; offset++) {
      bytes memory data = _randomBytes(offset + 20 + 17, bytes32(offset));
      bytes memory expected = _copy(data);

      data.replaceAddress(offset, addr);
      _apply(expected, offset, abi.encodePacked(addr));

      assertEq(data, expected);
    }
  }

  function test_replaceAddress_exactEndOffsets() public pure {
    address addr = address(0x111122223333444455556666777788889999aAaa);

    bytes memory data = _randomBytes(20, bytes32(uint256(1)));
    bytes memory expected = _copy(data);
    data.replaceAddress(0, addr);
    _apply(expected, 0, abi.encodePacked(addr));
    assertEq(data, expected);

    data = _randomBytes(32, bytes32(uint256(2)));
    expected = _copy(data);
    data.replaceAddress(12, addr); // ends exactly at 32, single-word path
    _apply(expected, 12, abi.encodePacked(addr));
    assertEq(data, expected);

    data = _randomBytes(33, bytes32(uint256(3)));
    expected = _copy(data);
    data.replaceAddress(13, addr); // ends exactly at 33, crosses word boundary
    _apply(expected, 13, abi.encodePacked(addr));
    assertEq(data, expected);

    data = _randomBytes(51, bytes32(uint256(4)));
    expected = _copy(data);
    data.replaceAddress(31, addr); // ends exactly at 51, crosses word boundary (1 + 19)
    _apply(expected, 31, abi.encodePacked(addr));
    assertEq(data, expected);
  }

  function test_replaceAddress_reverts_outOfBounds() public {
    bytes memory data = new bytes(19);
    vm.expectRevert();
    this._replaceAddress(data, 0, address(1));

    data = new bytes(20);
    vm.expectRevert();
    this._replaceAddress(data, 1, address(1));

    data = new bytes(0);
    vm.expectRevert();
    this._replaceAddress(data, 0, address(1));
  }

  function test_replaceAddress_reverts_overflowEnd() public {
    bytes memory data = new bytes(64);
    vm.expectRevert();
    this._replaceAddress(data, type(uint256).max - 10, address(1));
  }

  function testFuzz_replaceUint256(bytes32 seed, uint256 offset, uint256 val) public {
    uint256 len = bound(uint256(seed), 0, 256);
    bytes memory data = _randomBytes(len, seed);
    bytes memory expected = _copy(data);

    uint256 end;
    bool overflow;
    unchecked {
      end = offset + 32;
      overflow = end < offset;
    }

    if (overflow || end > len) {
      vm.expectRevert();
      this._replaceUint256(data, offset, val);
      return;
    }

    data.replaceUint256(offset, val);
    _apply(expected, offset, abi.encodePacked(val));
    assertEq(data, expected);
  }

  function testFuzz_replaceAddress(bytes32 seed, uint256 offset, address addr) public {
    uint256 len = bound(uint256(seed), 0, 256);
    bytes memory data = _randomBytes(len, seed);
    bytes memory expected = _copy(data);

    uint256 end;
    bool overflow;
    unchecked {
      end = offset + 20;
      overflow = end < offset;
    }

    if (overflow || end > len) {
      vm.expectRevert();
      this._replaceAddress(data, offset, addr);
      return;
    }

    data.replaceAddress(offset, addr);
    _apply(expected, offset, abi.encodePacked(addr));
    assertEq(data, expected);
  }
}
