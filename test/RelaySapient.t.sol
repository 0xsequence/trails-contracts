// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {RelaySapient} from "src/modules/RelaySapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

contract RelaySapientTest is Test {
  uint256 private constant SOLVER_PK = 0x50111E7;
  uint256 private constant FAKE_PK = 0xFA4E;

  RelaySapient internal sapient;
  address internal solver;
  address internal fakeSigner;

  address internal pdaAddress;
  address internal sendingAsset;
  address internal receiver;
  bytes32 internal receivingAssetId;
  uint256 internal destChainId;

  function setUp() external {
    solver = vm.addr(SOLVER_PK);
    fakeSigner = vm.addr(FAKE_PK);
    sapient = new RelaySapient(solver);

    pdaAddress = makeAddr("pda");
    sendingAsset = makeAddr("usdc-base");
    receiver = makeAddr("recipient");
    receivingAssetId = bytes32(uint256(uint160(makeAddr("usdc-eth"))));
    destChainId = 1;
  }

  function _buildPayload() internal pure returns (Payload.Decoded memory) {
    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(0x1234),
      value: 0,
      data: hex"deadbeef",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
    });

    return Payload.Decoded({
      kind: Payload.KIND_TRANSACTIONS,
      noChainId: false,
      calls: calls,
      space: 0,
      nonce: 0,
      message: "",
      imageHash: bytes32(0),
      digest: bytes32(0),
      parentWallets: new address[](0)
    });
  }

  function _signAttestation(
    uint256 pk,
    bytes32 requestId
  ) internal view returns (bytes memory) {
    bytes32 innerHash = keccak256(
      abi.encodePacked(
        requestId,
        block.chainid,
        bytes32(uint256(uint160(pdaAddress))),
        bytes32(uint256(uint160(sendingAsset))),
        destChainId,
        bytes32(uint256(uint160(receiver))),
        receivingAssetId
      )
    );
    bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", innerHash));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ethHash);
    return abi.encodePacked(r, s, v);
  }

  function _encodeSig(bytes32 requestId, bytes memory attestation) internal view returns (bytes memory) {
    return abi.encode(requestId, pdaAddress, sendingAsset, destChainId, receiver, receivingAssetId, attestation);
  }

  // --- Happy path ---

  function test_validAttestation_returnsFixedImageHash() external view {
    bytes32 requestId = keccak256("request-1");
    bytes memory attestation = _signAttestation(SOLVER_PK, requestId);
    bytes memory sig = _encodeSig(requestId, attestation);
    Payload.Decoded memory payload = _buildPayload();

    bytes32 result = sapient.recoverSapientSignature(payload, sig);

    bytes32 expected = sapient.imageHash(destChainId, receiver, receivingAssetId);
    assertEq(result, expected);
    assertTrue(result != bytes32(0));
  }

  function test_differentRequestIds_returnSameImageHash() external view {
    bytes32 req1 = keccak256("request-1");
    bytes32 req2 = keccak256("request-2");

    bytes memory sig1 = _encodeSig(req1, _signAttestation(SOLVER_PK, req1));
    bytes memory sig2 = _encodeSig(req2, _signAttestation(SOLVER_PK, req2));
    Payload.Decoded memory payload = _buildPayload();

    bytes32 hash1 = sapient.recoverSapientSignature(payload, sig1);
    bytes32 hash2 = sapient.recoverSapientSignature(payload, sig2);

    assertEq(hash1, hash2, "image hash must be stable across deposits");
  }

  // --- Invalid signer ---

  function test_wrongSigner_reverts() external {
    bytes32 requestId = keccak256("request-3");
    bytes memory attestation = _signAttestation(FAKE_PK, requestId);
    bytes memory sig = _encodeSig(requestId, attestation);
    Payload.Decoded memory payload = _buildPayload();

    vm.expectRevert(abi.encodeWithSelector(RelaySapient.InvalidRelaySolver.selector, fakeSigner));
    sapient.recoverSapientSignature(payload, sig);
  }

  // --- Tampered parameters ---

  function test_tamperedReceiver_reverts() external {
    bytes32 requestId = keccak256("request-4");
    bytes memory attestation = _signAttestation(SOLVER_PK, requestId);

    // Encode with a different receiver than what was signed
    address tamperedReceiver = makeAddr("attacker");
    bytes memory sig = abi.encode(
      requestId, pdaAddress, sendingAsset, destChainId, tamperedReceiver, receivingAssetId, attestation
    );
    Payload.Decoded memory payload = _buildPayload();

    vm.expectRevert(); // ECDSA recovery will produce wrong address
    sapient.recoverSapientSignature(payload, sig);
  }

  function test_tamperedDestChain_reverts() external {
    bytes32 requestId = keccak256("request-5");
    bytes memory attestation = _signAttestation(SOLVER_PK, requestId);

    uint256 tamperedChain = 137; // Polygon instead of Ethereum
    bytes memory sig = abi.encode(
      requestId, pdaAddress, sendingAsset, tamperedChain, receiver, receivingAssetId, attestation
    );
    Payload.Decoded memory payload = _buildPayload();

    vm.expectRevert();
    sapient.recoverSapientSignature(payload, sig);
  }

  // --- Non-transaction payload ---

  function test_nonTransactionPayload_reverts() external {
    bytes32 requestId = keccak256("request-6");
    bytes memory attestation = _signAttestation(SOLVER_PK, requestId);
    bytes memory sig = _encodeSig(requestId, attestation);

    Payload.Call[] memory calls = new Payload.Call[](0);
    Payload.Decoded memory payload = Payload.Decoded({
      kind: 0x01, // MESSAGE kind
      noChainId: false,
      calls: calls,
      space: 0,
      nonce: 0,
      message: "hello",
      imageHash: bytes32(0),
      digest: bytes32(0),
      parentWallets: new address[](0)
    });

    vm.expectRevert(RelaySapient.NonTransactionPayload.selector);
    sapient.recoverSapientSignature(payload, sig);
  }

  // --- imageHash helper ---

  function test_imageHash_deterministic() external view {
    bytes32 h1 = sapient.imageHash(destChainId, receiver, receivingAssetId);
    bytes32 h2 = sapient.imageHash(destChainId, receiver, receivingAssetId);
    assertEq(h1, h2);
  }

  function test_imageHash_differentParams_differentHash() external view {
    bytes32 h1 = sapient.imageHash(1, receiver, receivingAssetId);
    bytes32 h2 = sapient.imageHash(137, receiver, receivingAssetId);
    assertTrue(h1 != h2);
  }
}
