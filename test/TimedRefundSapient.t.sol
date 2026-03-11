// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Allowlist} from "src/autoRecovery/Allowlist.sol";
import {TimedRefundSapient} from "src/autoRecovery/TimedRefundSapient.sol";
import {MockERC20} from "test/helpers/Mocks.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

contract TimedRefundSapientTest is Test {
  uint256 private constant ALLOWED_SIGNER_PK = 0xA11CE;
  uint256 private constant BLOCKED_SIGNER_PK = 0xB0B;
  uint256 private constant START_TIME = 1_000;
  uint256 private constant MAX_METADATA_RETURN_LENGTH = 256;

  Allowlist internal allowlist;
  TimedRefundSapient internal sapient;
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
    sapient = new TimedRefundSapient(allowlist);

    token = new MockERC20();
    token.mint(wallet, 1_000 ether);
  }

  function test_recoverSapientSignature_reverts_invalidAllowSignatureLength() external {
    Payload.Decoded memory payload = _erc20Payload();
    bytes memory signature = abi.encode(destination, START_TIME, bytes(""));

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(TimedRefundSapient.InvalidApprovalSignatureLength.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, signature);
  }

  function test_recoverSapientSignature_reverts_invalidRecoveredSigner() external {
    Payload.Decoded memory payload = _erc20Payload();
    bytes memory signature = abi.encode(destination, START_TIME, new bytes(64));

    vm.prank(wallet);
    vm.expectRevert(TimedRefundSapient.InvalidRecoveredSigner.selector);
    sapient.recoverSapientSignature(payload, signature);
  }

  function test_recoverSapientSignature_reverts_signerNotAllowed() external {
    Payload.Decoded memory payload = _erc20Payload();
    bytes memory signature = _signatureFor(payload, wallet, BLOCKED_SIGNER_PK, destination, START_TIME);

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(TimedRefundSapient.SignerNotAllowed.selector, blockedSigner));
    sapient.recoverSapientSignature(payload, signature);
  }

  function test_recoverSapientSignature_reverts_unlockTimestampNotReached() external {
    Payload.Decoded memory payload = _erc20Payload();
    uint256 unlockTimestamp = block.timestamp + 1;

    vm.prank(wallet);
    vm.expectRevert(
      abi.encodeWithSelector(TimedRefundSapient.UnlockTimestampNotReached.selector, unlockTimestamp, block.timestamp)
    );
    sapient.recoverSapientSignature(
      payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, unlockTimestamp)
    );
  }

  function test_recoverSapientSignature_reverts_invalidPayloadKind() external {
    Payload.Decoded memory payload = Payload.fromMessage(bytes("recovery"));

    vm.prank(wallet);
    vm.expectRevert(
      abi.encodeWithSelector(TimedRefundSapient.InvalidPayloadKind.selector, uint256(Payload.KIND_MESSAGE))
    );
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_invalidNonceSpace() external {
    Payload.Decoded memory payload = _erc20Payload();
    payload.space = sapient.TIMED_REFUND_NONCE_SPACE() ^ 1;

    vm.prank(wallet);
    vm.expectRevert(
      abi.encodeWithSelector(
        TimedRefundSapient.InvalidNonceSpace.selector, payload.space, sapient.TIMED_REFUND_NONCE_SPACE()
      )
    );
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function testFuzz_hasERC20Metadata_returnsExpectedForArbitraryMetadataResponses(
    bytes memory nameData,
    bool nameReverts,
    bytes memory symbolData,
    bool symbolReverts
  ) external {
    vm.assume(nameData.length <= MAX_METADATA_RETURN_LENGTH);
    vm.assume(symbolData.length <= MAX_METADATA_RETURN_LENGTH);

    _mockMetadata(address(token), nameData, nameReverts, symbolData, symbolReverts);

    bool expected = _metadataProbeSucceeds(nameData, nameReverts) && _metadataProbeSucceeds(symbolData, symbolReverts);
    assertEq(sapient.hasERC20Metadata(address(token)), expected);
  }

  function test_hasERC20Metadata_returnsFalse_forAddressWithoutCode() external {
    assertFalse(sapient.hasERC20Metadata(makeAddr("externallyOwnedAccount")));
  }

  function test_recoverSapientSignature_returnsRoot_forErc20TransferPayload() external {
    Payload.Decoded memory payload = _erc20Payload();
    uint256 unlockTimestamp = block.timestamp;

    vm.prank(wallet);
    bytes32 got = sapient.recoverSapientSignature(
      payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, unlockTimestamp)
    );

    assertEq(got, keccak256(abi.encode("timed-refund", destination, unlockTimestamp)));
  }

  function testFuzz_recoverSapientSignature_returnsRoot_whenMetadataProbesReturnNonEmptyData(
    bytes memory nameData,
    bytes memory symbolData
  ) external {
    vm.assume(nameData.length > 0 && nameData.length <= MAX_METADATA_RETURN_LENGTH);
    vm.assume(symbolData.length > 0 && symbolData.length <= MAX_METADATA_RETURN_LENGTH);

    _mockMetadata(address(token), nameData, false, symbolData, false);
    Payload.Decoded memory payload = _erc20Payload();
    uint256 unlockTimestamp = block.timestamp;

    vm.prank(wallet);
    bytes32 got = sapient.recoverSapientSignature(
      payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, unlockTimestamp)
    );

    assertEq(got, keccak256(abi.encode("timed-refund", destination, unlockTimestamp)));
  }

  function test_recoverSapientSignature_returnsRoot_forMixedTransferBatch() external {
    Payload.Decoded memory payload = _mixedTransferPayload();
    uint256 unlockTimestamp = block.timestamp - 100;

    vm.prank(wallet);
    bytes32 got = sapient.recoverSapientSignature(
      payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, unlockTimestamp)
    );

    assertEq(got, keccak256(abi.encode("timed-refund", destination, unlockTimestamp)));
  }

  function test_recoverSapientSignature_reverts_whenSignatureWasSignedForDifferentWallet() external {
    Payload.Decoded memory payload = _erc20Payload();
    bytes32 signedDigest = Payload.hashFor(payload, otherWallet);
    bytes memory allowSignature = _compactSignature(signedDigest, ALLOWED_SIGNER_PK);
    bytes memory signature = abi.encode(destination, START_TIME, allowSignature);
    address recoveredSigner = _recoverCompactSigner(Payload.hashFor(payload, wallet), allowSignature);

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(TimedRefundSapient.SignerNotAllowed.selector, recoveredSigner));
    sapient.recoverSapientSignature(payload, signature);
  }

  function test_recoverSapientSignature_reverts_invalidBehaviorOnError() external {
    Payload.Decoded memory payload = _mixedTransferPayload();
    payload.calls[1].behaviorOnError = Payload.BEHAVIOR_IGNORE_ERROR;

    vm.prank(wallet);
    vm.expectRevert(
      abi.encodeWithSelector(
        TimedRefundSapient.InvalidBehaviorOnError.selector, uint256(1), uint256(Payload.BEHAVIOR_IGNORE_ERROR)
      )
    );
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_delegateCallNotAllowed() external {
    Payload.Decoded memory payload = _erc20Payload();
    payload.calls[0].delegateCall = true;

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(TimedRefundSapient.DelegateCallNotAllowed.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_onlyFallbackNotAllowed() external {
    Payload.Decoded memory payload = _erc20Payload();
    payload.calls[0].onlyFallback = true;

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(TimedRefundSapient.OnlyFallbackNotAllowed.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_gasLimitNotZero() external {
    Payload.Decoded memory payload = _erc20Payload();
    payload.calls[0].gasLimit = 1;

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(TimedRefundSapient.GasLimitNotZero.selector, uint256(0), uint256(1)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function testFuzz_recoverSapientSignature_reverts_unauthorizedTransaction_whenMetadataProbeFails(
    bytes memory nameData,
    bool nameReverts,
    bytes memory symbolData,
    bool symbolReverts
  ) external {
    vm.assume(nameData.length <= MAX_METADATA_RETURN_LENGTH);
    vm.assume(symbolData.length <= MAX_METADATA_RETURN_LENGTH);
    vm.assume(!_metadataProbeSucceeds(nameData, nameReverts) || !_metadataProbeSucceeds(symbolData, symbolReverts));

    _mockMetadata(address(token), nameData, nameReverts, symbolData, symbolReverts);
    Payload.Decoded memory payload = _erc20Payload();

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(TimedRefundSapient.UnauthorizedTransaction.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_unauthorizedTransaction_whenTokenAddressHasNoCode() external {
    Payload.Decoded memory payload = _erc20PayloadFor(makeAddr("noCodeToken"));

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(TimedRefundSapient.UnauthorizedTransaction.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_unauthorizedTransaction_forShortErc20Calldata() external {
    Payload.Decoded memory payload = _erc20Payload();
    payload.calls[0].data = abi.encodePacked(MockERC20.transfer.selector);

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(TimedRefundSapient.UnauthorizedTransaction.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_unauthorizedTransaction_forWrongErc20Selector() external {
    Payload.Decoded memory payload = _erc20Payload();
    payload.calls[0].data = abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), destination, 123);

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(TimedRefundSapient.UnauthorizedTransaction.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_unauthorizedTransaction_forWrongErc20Recipient() external {
    Payload.Decoded memory payload = _erc20Payload();
    payload.calls[0].data = abi.encodeCall(MockERC20.transfer, (makeAddr("otherDestination"), 123));

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(TimedRefundSapient.UnauthorizedTransaction.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_unauthorizedTransaction_forWrongNativeRecipient() external {
    Payload.Decoded memory payload = _nativePayload();
    payload.calls[0].to = makeAddr("otherRecipient");

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(TimedRefundSapient.UnauthorizedTransaction.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function test_recoverSapientSignature_reverts_nativeTransferDataNotEmpty() external {
    Payload.Decoded memory payload = _nativePayload();
    payload.calls[0].data = hex"deadbeef";

    vm.prank(wallet);
    vm.expectRevert(
      abi.encodeWithSelector(TimedRefundSapient.NativeTransferDataNotEmpty.selector, uint256(0), uint256(4))
    );
    sapient.recoverSapientSignature(payload, _signatureFor(payload, wallet, ALLOWED_SIGNER_PK, destination, START_TIME));
  }

  function _erc20Payload() private view returns (Payload.Decoded memory payload) {
    return _erc20PayloadFor(address(token));
  }

  function _erc20PayloadFor(address token_) private view returns (Payload.Decoded memory payload) {
    payload.kind = Payload.KIND_TRANSACTIONS;
    payload.space = sapient.TIMED_REFUND_NONCE_SPACE();
    payload.nonce = 42;
    payload.calls = new Payload.Call[](1);
    payload.calls[0] = _erc20TransferCall(token_, 123);
  }

  function _nativePayload() private view returns (Payload.Decoded memory payload) {
    payload.kind = Payload.KIND_TRANSACTIONS;
    payload.space = sapient.TIMED_REFUND_NONCE_SPACE();
    payload.nonce = 42;
    payload.calls = new Payload.Call[](1);
    payload.calls[0] = _nativeTransferCall(1 ether);
  }

  function _mixedTransferPayload() private view returns (Payload.Decoded memory payload) {
    payload.kind = Payload.KIND_TRANSACTIONS;
    payload.noChainId = true;
    payload.space = sapient.TIMED_REFUND_NONCE_SPACE();
    payload.nonce = 99;
    payload.calls = new Payload.Call[](2);
    payload.calls[0] = _erc20TransferCall(address(token), 123);
    payload.calls[1] = _nativeTransferCall(1 ether);
  }

  function _erc20TransferCall(address token_, uint256 amount) private view returns (Payload.Call memory) {
    return Payload.Call({
      to: token_,
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
    uint256 unlockTimestamp
  ) private view returns (bytes memory) {
    bytes32 payloadHash = Payload.hashFor(payload, wallet_);
    return abi.encode(destination_, unlockTimestamp, _compactSignature(payloadHash, signerPk));
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

  function _mockMetadata(
    address token_,
    bytes memory nameData,
    bool nameReverts,
    bytes memory symbolData,
    bool symbolReverts
  ) private {
    if (nameReverts) {
      vm.mockCallRevert(token_, abi.encodeCall(IERC20Metadata.name, ()), bytes("metadata"));
    } else {
      vm.mockCall(token_, abi.encodeCall(IERC20Metadata.name, ()), nameData);
    }

    if (symbolReverts) {
      vm.mockCallRevert(token_, abi.encodeCall(IERC20Metadata.symbol, ()), bytes("metadata"));
    } else {
      vm.mockCall(token_, abi.encodeCall(IERC20Metadata.symbol, ()), symbolData);
    }
  }

  function _metadataProbeSucceeds(bytes memory returnData, bool reverts) private pure returns (bool) {
    return !reverts && returnData.length != 0;
  }
}
