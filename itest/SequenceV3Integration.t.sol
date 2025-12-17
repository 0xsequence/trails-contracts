// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import "forge-std/Test.sol";

import {TrailsUtils} from "src/TrailsUtils.sol";

import {PackedPayload} from "trails-test/helpers/PackedPayload.sol";
import {RecordingReceiver} from "trails-test/helpers/Mocks.sol";

import {Factory as SeqFactory} from "wallet-contracts-v3-external/Factory.sol";
import {Stage1Module as SeqStage1Module} from "wallet-contracts-v3-external/Stage1Module.sol";
import {Payload as SeqPayload} from "wallet-contracts-v3-external/modules/Payload.sol";
import {ISapient} from "wallet-contracts-v3-external/modules/interfaces/ISapient.sol";

import {Payload as LocalPayload} from "wallet-contracts-v3/modules/Payload.sol";

contract SequenceV3IntegrationTest is Test {
  using PackedPayload for LocalPayload.Call[];

  function _fkeccak(bytes32 a, bytes32 b) private pure returns (bytes32 c) {
    assembly ("memory-safe") {
      mstore(0, a)
      mstore(32, b)
      c := keccak256(0, 64)
    }
  }

  function _leafForSapient(address signer, uint256 weight, bytes32 sapientImageHash) private pure returns (bytes32) {
    return keccak256(abi.encodePacked("Sequence sapient config:\n", signer, weight, sapientImageHash));
  }

  function _configImageHashForSapient(bytes32 sapientImageHash, address sapient, uint256 weight, uint256 threshold)
    private
    pure
    returns (bytes32)
  {
    bytes32 root = _leafForSapient(sapient, weight, sapientImageHash);
    bytes32 imageHash = _fkeccak(root, bytes32(threshold));
    imageHash = _fkeccak(imageHash, bytes32(0)); // checkpoint
    imageHash = _fkeccak(imageHash, bytes32(0)); // checkpointer
    return imageHash;
  }

  function _buildSapientSignature(address sapient, uint8 weight, uint8 threshold, bytes memory sapientSig)
    private
    pure
    returns (bytes memory sig)
  {
    require(weight > 0, "weight=0");
    require(threshold > 0, "threshold=0");

    uint8 signatureFlag = 0x00; // normal sig, checkpointSize=0, thresholdSize=1, noChainId=false

    uint8 weightBits = weight <= 3 ? weight : 0;
    bytes memory weightExtra = weightBits == 0 ? abi.encodePacked(weight) : bytes("");

    uint256 len = sapientSig.length;
    uint8 sizeSize;
    bytes memory sizeBytes;
    if (len == 0) {
      sizeSize = 0;
      sizeBytes = "";
    } else if (len <= type(uint8).max) {
      sizeSize = 1;
      sizeBytes = abi.encodePacked(uint8(len));
    } else if (len <= type(uint16).max) {
      sizeSize = 2;
      sizeBytes = abi.encodePacked(uint16(len));
    } else if (len <= type(uint24).max) {
      sizeSize = 3;
      sizeBytes = abi.encodePacked(uint24(len));
    } else {
      revert("sapientSig-too-large");
    }

    uint8 header = uint8(0x90 | (sizeSize << 2) | weightBits);
    sig = bytes.concat(
      abi.encodePacked(signatureFlag, threshold, header),
      weightExtra,
      abi.encodePacked(sapient),
      sizeBytes,
      sapientSig
    );
  }

  function _readAddress(bytes memory data, uint256 offset) private pure returns (address a) {
    assembly ("memory-safe") {
      a := shr(96, mload(add(add(data, 32), offset)))
    }
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

  function _asSeqCall(LocalPayload.Call memory c) private pure returns (SeqPayload.Call memory) {
    return SeqPayload.Call({
      to: c.to,
      value: c.value,
      data: c.data,
      gasLimit: c.gasLimit,
      delegateCall: c.delegateCall,
      onlyFallback: c.onlyFallback,
      behaviorOnError: c.behaviorOnError
    });
  }

  function testFuzz_integration_sapientSigner_allowsMalleableCalldata(bytes32 seed) external {
    TrailsUtils trailsUtils = new TrailsUtils();

    SeqFactory factory = new SeqFactory();
    SeqStage1Module stage1 = new SeqStage1Module(address(factory), address(0));

    RecordingReceiver receiver = new RecordingReceiver();

    bytes4 marker = 0xdeadbeef;
    bytes memory dataA = _randomBytes(64, keccak256(abi.encodePacked(seed, "a")));
    bytes memory dataB = _randomBytes(64, keccak256(abi.encodePacked(seed, "b")));
    assembly {
      mstore(add(dataA, 32), marker)
      mstore(add(dataB, 32), marker)
    }

    LocalPayload.Call[] memory calls = new LocalPayload.Call[](1);
    calls[0] = LocalPayload.Call({
      to: address(receiver),
      value: 0,
      data: dataB, // execute with "malleable" bytes
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: 0
    });

    bytes memory packedPayload = calls.packCalls();

    SeqPayload.Decoded memory payload;
    payload.kind = SeqPayload.KIND_TRANSACTIONS;
    payload.calls = new SeqPayload.Call[](1);
    payload.calls[0] = _asSeqCall(
      LocalPayload.Call({
        to: address(receiver),
        value: 0,
        data: dataA, // compute config with "static" bytes only
        gasLimit: 0,
        delegateCall: false,
        onlyFallback: false,
        behaviorOnError: 0
      })
    );
    payload.space = 0;
    payload.nonce = 0;

    // Commit to only the first 4 bytes of call[0].data.
    bytes memory sapientSig = abi.encodePacked(uint8(0), uint16(0), uint16(4));
    bytes32 sapientImageHash = ISapient(address(trailsUtils)).recoverSapientSignature(payload, sapientSig);

    bytes32 configImageHash = _configImageHashForSapient(sapientImageHash, address(trailsUtils), 1, 1);
    address wallet = factory.deploy(address(stage1), configImageHash);

    bytes memory signature = _buildSapientSignature(address(trailsUtils), 1, 1, sapientSig);

    SeqStage1Module(payable(wallet)).execute(packedPayload, signature);

    assertEq(receiver.lastSender(), wallet);
    assertEq(receiver.lastData(), dataB);
  }

  function test_integration_walletDelegatecallsHydrateProxy_andHydrates() external {
    TrailsUtils trailsUtils = new TrailsUtils();

    SeqFactory factory = new SeqFactory();
    SeqStage1Module stage1 = new SeqStage1Module(address(factory), address(0));

    RecordingReceiver receiver = new RecordingReceiver();

    bytes memory innerData = new bytes(64);
    LocalPayload.Call[] memory innerCalls = new LocalPayload.Call[](1);
    innerCalls[0] = LocalPayload.Call({
      to: address(receiver),
      value: 0,
      data: innerData,
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: 0
    });

    bytes memory innerPacked = innerCalls.packCalls();

    // Hydrate call 0:
    // - insert `address(this)` (wallet) at offset 0
    // - insert `msg.sender` (relayer) at offset 32
    bytes memory hydratePayload = bytes.concat(
      abi.encodePacked(uint8(0)), // tindex
      abi.encodePacked(uint8(0x01), uint16(0)), // HYDRATE_DATA_SELF_ADDRESS
      abi.encodePacked(uint8(0x02), uint16(32)), // HYDRATE_DATA_MESSAGE_SENDER_ADDRESS
      abi.encodePacked(uint8(0x00)) // SIGNAL_NEXT_HYDRATE
    );

    LocalPayload.Call[] memory outerCalls = new LocalPayload.Call[](1);
    outerCalls[0] = LocalPayload.Call({
      to: address(trailsUtils),
      value: 0,
      data: abi.encode(innerPacked, hydratePayload),
      gasLimit: 0,
      delegateCall: true,
      onlyFallback: false,
      behaviorOnError: 0
    });

    bytes memory outerPacked = outerCalls.packCalls();

    // Empty sapient signature => commit to call metadata only.
    bytes memory sapientSig = "";

    SeqPayload.Decoded memory payload;
    payload.kind = SeqPayload.KIND_TRANSACTIONS;
    payload.calls = new SeqPayload.Call[](1);
    payload.calls[0] = SeqPayload.Call({
      to: address(trailsUtils),
      value: 0,
      data: "", // unused (sapientSig is empty)
      gasLimit: 0,
      delegateCall: true,
      onlyFallback: false,
      behaviorOnError: 0
    });
    payload.space = 0;
    payload.nonce = 0;

    bytes32 sapientImageHash = ISapient(address(trailsUtils)).recoverSapientSignature(payload, sapientSig);
    bytes32 configImageHash = _configImageHashForSapient(sapientImageHash, address(trailsUtils), 1, 1);
    address wallet = factory.deploy(address(stage1), configImageHash);

    bytes memory signature = _buildSapientSignature(address(trailsUtils), 1, 1, sapientSig);

    address relayer = makeAddr("relayer");
    address origin = makeAddr("origin");
    vm.prank(relayer, origin);
    SeqStage1Module(payable(wallet)).execute(outerPacked, signature);

    assertEq(receiver.lastSender(), wallet);

    bytes memory got = receiver.lastData();
    assertEq(_readAddress(got, 0), wallet);
    assertEq(_readAddress(got, 32), relayer);
  }
}
