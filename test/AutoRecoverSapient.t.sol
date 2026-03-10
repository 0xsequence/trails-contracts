// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {Allowlist} from "src/autoRecovery/Allowlist.sol";
import {AutoRecoverSapient} from "src/autoRecovery/AutoRecoverSapient.sol";
import {MockERC20} from "test/helpers/Mocks.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

contract AutoRecoverSapientTest is Test {
  uint256 private constant ALLOWED_SIGNER_PK = 0xA11CE;
  uint256 private constant BLOCKED_SIGNER_PK = 0xB0B;
  uint256 private constant START_TIME = 1_000;

  Allowlist internal allowlist;
  AutoRecoverSapient internal sapient;
  MockERC20 internal token;

  address internal allowedSigner;
  address internal blockedSigner;
  address internal wallet;
  address internal otherWallet;
  address internal destination;

  function setUp() external {
    vm.warp(START_TIME);

    allowedSigner = vm.addr(ALLOWED_SIGNER_PK);
    blockedSigner = vm.addr(BLOCKED_SIGNER_PK);
    wallet = makeAddr("wallet");
    otherWallet = makeAddr("otherWallet");
    destination = makeAddr("destination");

    address[] memory initial = new address[](1);
    initial[0] = allowedSigner;

    allowlist = new Allowlist(address(this), initial);
    sapient = new AutoRecoverSapient(allowlist);

    token = new MockERC20();
    token.mint(wallet, 1_000 ether);
  }

  function test_recoverSapientSignature_reverts_invalidAllowSignatureLength() external {
    Payload.Decoded memory payload = _erc20Payload();
    bytes memory signature = abi.encode(destination, START_TIME, bytes(""));

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(AutoRecoverSapient.InvalidAllowSignatureLength.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, signature);
  }

  function test_recoverSapientSignature_reverts_invalidRecoveredSigner() external {
    Payload.Decoded memory payload = _erc20Payload();
    bytes memory signature = abi.encode(destination, START_TIME, new bytes(64));

    vm.prank(wallet);
    vm.expectRevert(AutoRecoverSapient.InvalidRecoveredSigner.selector);
    sapient.recoverSapientSignature(payload, signature);
  }

  function test_recoverSapientSignature_reverts_signerNotAllowed() external {
    Payload.Decoded memory payload = _erc20Payload();
    bytes memory signature = _signatureFor(payload, wallet, BLOCKED_SIGNER_PK, destination, START_TIME);

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(AutoRecoverSapient.SignerNotAllowed.selector, blockedSigner));
    sapient.recoverSapientSignature(payload, signature);
  }

  function test_recoverSapientSignature_reverts_thresholdNotReached() external {
    Payload.Decoded memory payload = _erc20Payload();
    uint256 threshold = block.timestamp + 1;

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(AutoRecoverSapient.ThresholdNotReached.selector, threshold, block.timestamp));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, threshold));
  }

  function test_recoverSapientSignature_reverts_invalidPayloadKind() external {
    Payload.Decoded memory payload = Payload.fromMessage(bytes("recovery"));

    vm.prank(wallet);
    vm.expectRevert(
      abi.encodeWithSelector(AutoRecoverSapient.InvalidPayloadKind.selector, uint256(Payload.KIND_MESSAGE))
    );
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_returnsRoot_forErc20TransferPayload() external {
    Payload.Decoded memory payload = _erc20Payload();
    uint256 threshold = block.timestamp;

    vm.prank(wallet);
    bytes32 got = sapient.recoverSapientSignature(
      payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, threshold)
    );

    assertEq(got, keccak256(abi.encode("auto-recover", destination, threshold)));
  }

  function test_recoverSapientSignature_returnsRoot_forMixedTransferBatch() external {
    Payload.Decoded memory payload = _mixedTransferPayload();
    uint256 threshold = block.timestamp - 100;

    vm.prank(wallet);
    bytes32 got = sapient.recoverSapientSignature(
      payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, threshold)
    );

    assertEq(got, keccak256(abi.encode("auto-recover", destination, threshold)));
  }

  function test_recoverSapientSignature_reverts_whenSignatureWasSignedForDifferentWallet() external {
    Payload.Decoded memory payload = _erc20Payload();
    bytes32 signedDigest = Payload.hashFor(payload, otherWallet);
    bytes memory allowSignature = _compactSignature(signedDigest, ALLOWED_SIGNER_PK);
    bytes memory signature = abi.encode(destination, START_TIME, allowSignature);
    address recoveredSigner = _recoverCompactSigner(Payload.hashFor(payload, wallet), allowSignature);

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(AutoRecoverSapient.SignerNotAllowed.selector, recoveredSigner));
    sapient.recoverSapientSignature(payload, signature);
  }

  function test_recoverSapientSignature_reverts_invalidBehaviorOnError() external {
    Payload.Decoded memory payload = _mixedTransferPayload();
    payload.calls[1].behaviorOnError = Payload.BEHAVIOR_IGNORE_ERROR;

    vm.prank(wallet);
    vm.expectRevert(
      abi.encodeWithSelector(
        AutoRecoverSapient.InvalidBehaviorOnError.selector, uint256(1), uint256(Payload.BEHAVIOR_IGNORE_ERROR)
      )
    );
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_delegateCallNotAllowed() external {
    Payload.Decoded memory payload = _erc20Payload();
    payload.calls[0].delegateCall = true;

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(AutoRecoverSapient.DelegateCallNotAllowed.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_onlyFallbackNotAllowed() external {
    Payload.Decoded memory payload = _erc20Payload();
    payload.calls[0].onlyFallback = true;

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(AutoRecoverSapient.OnlyFallbackNotAllowed.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_gasLimitNotZero() external {
    Payload.Decoded memory payload = _erc20Payload();
    payload.calls[0].gasLimit = 1;

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(AutoRecoverSapient.GasLimitNotZero.selector, uint256(0), uint256(1)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_unauthorizedTransaction_forShortErc20Calldata() external {
    Payload.Decoded memory payload = _erc20Payload();
    payload.calls[0].data = abi.encodePacked(MockERC20.transfer.selector);

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(AutoRecoverSapient.UnauthorizedTransaction.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_unauthorizedTransaction_forWrongErc20Selector() external {
    Payload.Decoded memory payload = _erc20Payload();
    payload.calls[0].data = abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), destination, 123);

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(AutoRecoverSapient.UnauthorizedTransaction.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_unauthorizedTransaction_forWrongErc20Recipient() external {
    Payload.Decoded memory payload = _erc20Payload();
    payload.calls[0].data = abi.encodeCall(MockERC20.transfer, (makeAddr("otherDestination"), 123));

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(AutoRecoverSapient.UnauthorizedTransaction.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_unauthorizedTransaction_forWrongNativeRecipient() external {
    Payload.Decoded memory payload = _nativePayload();
    payload.calls[0].to = makeAddr("otherRecipient");

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(AutoRecoverSapient.UnauthorizedTransaction.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_nativeTransferDataNotEmpty() external {
    Payload.Decoded memory payload = _nativePayload();
    payload.calls[0].data = hex"deadbeef";

    vm.prank(wallet);
    vm.expectRevert(
      abi.encodeWithSelector(AutoRecoverSapient.NativeTransferDataNotEmpty.selector, uint256(0), uint256(4))
    );
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function _erc20Payload() private view returns (Payload.Decoded memory payload) {
    payload.kind = Payload.KIND_TRANSACTIONS;
    payload.space = 7;
    payload.nonce = 42;
    payload.calls = new Payload.Call[](1);
    payload.calls[0] = _erc20TransferCall(123);
  }

  function _nativePayload() private view returns (Payload.Decoded memory payload) {
    payload.kind = Payload.KIND_TRANSACTIONS;
    payload.space = 7;
    payload.nonce = 42;
    payload.calls = new Payload.Call[](1);
    payload.calls[0] = _nativeTransferCall(1 ether);
  }

  function _mixedTransferPayload() private view returns (Payload.Decoded memory payload) {
    payload.kind = Payload.KIND_TRANSACTIONS;
    payload.noChainId = true;
    payload.space = 11;
    payload.nonce = 99;
    payload.calls = new Payload.Call[](2);
    payload.calls[0] = _erc20TransferCall(123);
    payload.calls[1] = _nativeTransferCall(1 ether);
  }

  function _erc20TransferCall(uint256 amount) private view returns (Payload.Call memory) {
    return Payload.Call({
      to: address(token),
      value: 0,
      data: abi.encodeCall(MockERC20.transfer, (destination, amount)),
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
    });
  }

  function _nativeTransferCall(uint256 amount) private view returns (Payload.Call memory) {
    return Payload.Call({
      to: destination,
      value: amount,
      data: "",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
    });
  }

  function _signatureFor(
    Payload.Decoded memory payload,
    address wallet_,
    uint256 signerPk,
    address destination_,
    uint256 threshold
  ) private view returns (bytes memory) {
    bytes32 payloadHash = Payload.hashFor(payload, wallet_);
    return abi.encode(destination_, threshold, _compactSignature(payloadHash, signerPk));
  }

  function _compactSignature(bytes32 digest, uint256 privateKey) private pure returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    bytes32 yParityAndS = bytes32((uint256(s) & ((uint256(1) << 255) - 1)) | (uint256(v - 27) << 255));
    return abi.encodePacked(r, yParityAndS);
  }

  function _recoverCompactSigner(bytes32 digest, bytes memory signature) private pure returns (address) {
    bytes32 r;
    bytes32 s;
    uint8 v;

    assembly {
      r := mload(add(signature, 0x20))
      let yParityAndS := mload(add(signature, 0x40))
      v := add(shr(255, yParityAndS), 27)
      s := and(yParityAndS, sub(shl(255, 1), 1))
    }

    return ecrecover(digest, v, r, s);
  }
}
