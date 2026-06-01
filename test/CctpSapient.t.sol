// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {CctpSapient} from "src/modules/CctpSapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

contract CctpSapientTest is Test {
  CctpSapient internal sapient;

  address internal tokenMessenger;
  address internal burnToken;
  uint32 internal destDomain;
  bytes32 internal mintRecipient;

  function setUp() external {
    tokenMessenger = makeAddr("tokenMessenger");
    burnToken = makeAddr("usdc");
    destDomain = 0; // Ethereum domain in CCTP
    mintRecipient = bytes32(uint256(uint160(makeAddr("recipient"))));

    sapient = new CctpSapient(tokenMessenger);
  }

  function _encodeDepositForBurn(
    uint256 amount,
    uint32 _destDomain,
    bytes32 _mintRecipient,
    address _burnToken,
    bytes32 destCaller,
    uint256 maxFee,
    uint32 minFinalityThreshold
  ) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(
      bytes4(0x2eca2558), // depositForBurn selector
      amount,
      _destDomain,
      _mintRecipient,
      _burnToken,
      destCaller,
      maxFee,
      minFinalityThreshold
    );
  }

  function _buildPayload(bytes memory depositCalldata) internal view returns (Payload.Decoded memory) {
    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: tokenMessenger,
      value: 0,
      data: depositCalldata,
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

  function _encodeSig(uint8 callIndex) internal view returns (bytes memory) {
    return abi.encode(callIndex, destDomain, mintRecipient, burnToken);
  }

  // --- Happy path ---

  function test_validDepositForBurn_returnsFixedImageHash() external view {
    bytes memory calldata_ = _encodeDepositForBurn(
      1_000_000, destDomain, mintRecipient, burnToken, bytes32(0), 1000, 0
    );
    Payload.Decoded memory payload = _buildPayload(calldata_);
    bytes memory sig = _encodeSig(0);

    bytes32 result = sapient.recoverSapientSignature(payload, sig);

    bytes32 expected = sapient.imageHash(destDomain, mintRecipient, burnToken);
    assertEq(result, expected);
    assertTrue(result != bytes32(0));
  }

  function test_differentAmounts_returnSameImageHash() external view {
    bytes memory call1 = _encodeDepositForBurn(
      1_000_000, destDomain, mintRecipient, burnToken, bytes32(0), 1000, 0
    );
    bytes memory call2 = _encodeDepositForBurn(
      50_000_000, destDomain, mintRecipient, burnToken, bytes32(0), 5000, 0
    );

    bytes32 hash1 = sapient.recoverSapientSignature(_buildPayload(call1), _encodeSig(0));
    bytes32 hash2 = sapient.recoverSapientSignature(_buildPayload(call2), _encodeSig(0));

    assertEq(hash1, hash2, "image hash must be stable regardless of amount");
  }

  // --- Wrong destination domain ---

  function test_wrongDestDomain_reverts() external {
    uint32 wrongDomain = 3; // Avalanche instead of Ethereum
    bytes memory calldata_ = _encodeDepositForBurn(
      1_000_000, wrongDomain, mintRecipient, burnToken, bytes32(0), 1000, 0
    );
    Payload.Decoded memory payload = _buildPayload(calldata_);
    bytes memory sig = _encodeSig(0);

    vm.expectRevert(
      abi.encodeWithSelector(CctpSapient.InvalidDestinationDomain.selector, wrongDomain, destDomain)
    );
    sapient.recoverSapientSignature(payload, sig);
  }

  // --- Wrong mint recipient ---

  function test_wrongMintRecipient_reverts() external {
    bytes32 wrongRecipient = bytes32(uint256(uint160(makeAddr("attacker"))));
    bytes memory calldata_ = _encodeDepositForBurn(
      1_000_000, destDomain, wrongRecipient, burnToken, bytes32(0), 1000, 0
    );
    Payload.Decoded memory payload = _buildPayload(calldata_);
    bytes memory sig = _encodeSig(0);

    vm.expectRevert(
      abi.encodeWithSelector(CctpSapient.InvalidMintRecipient.selector, wrongRecipient, mintRecipient)
    );
    sapient.recoverSapientSignature(payload, sig);
  }

  // --- Wrong burn token ---

  function test_wrongBurnToken_reverts() external {
    address wrongToken = makeAddr("fake-token");
    bytes memory calldata_ = _encodeDepositForBurn(
      1_000_000, destDomain, mintRecipient, wrongToken, bytes32(0), 1000, 0
    );
    Payload.Decoded memory payload = _buildPayload(calldata_);
    bytes memory sig = _encodeSig(0);

    vm.expectRevert(
      abi.encodeWithSelector(CctpSapient.InvalidBurnToken.selector, wrongToken, burnToken)
    );
    sapient.recoverSapientSignature(payload, sig);
  }

  // --- Wrong selector ---

  function test_wrongSelector_reverts() external {
    bytes memory calldata_ = abi.encodeWithSelector(
      bytes4(0xdeadbeef), uint256(1_000_000)
    );
    Payload.Decoded memory payload = _buildPayload(calldata_);
    bytes memory sig = _encodeSig(0);

    vm.expectRevert(CctpSapient.NoDepositForBurnCall.selector);
    sapient.recoverSapientSignature(payload, sig);
  }

  // --- Non-transaction payload ---

  function test_nonTransactionPayload_reverts() external {
    Payload.Call[] memory calls = new Payload.Call[](0);
    Payload.Decoded memory payload = Payload.Decoded({
      kind: 0x01,
      noChainId: false,
      calls: calls,
      space: 0,
      nonce: 0,
      message: "hello",
      imageHash: bytes32(0),
      digest: bytes32(0),
      parentWallets: new address[](0)
    });
    bytes memory sig = _encodeSig(0);

    vm.expectRevert(CctpSapient.NonTransactionPayload.selector);
    sapient.recoverSapientSignature(payload, sig);
  }

  // --- imageHash determinism ---

  function test_imageHash_deterministic() external view {
    bytes32 h1 = sapient.imageHash(destDomain, mintRecipient, burnToken);
    bytes32 h2 = sapient.imageHash(destDomain, mintRecipient, burnToken);
    assertEq(h1, h2);
  }

  function test_imageHash_differentDomain_differentHash() external view {
    bytes32 h1 = sapient.imageHash(0, mintRecipient, burnToken);
    bytes32 h2 = sapient.imageHash(3, mintRecipient, burnToken);
    assertTrue(h1 != h2);
  }
}
