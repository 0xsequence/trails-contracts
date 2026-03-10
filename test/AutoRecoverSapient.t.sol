// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {Allowlist} from "src/autoRecovery/Allowlist.sol";
import {AutoRecoverSapient} from "src/autoRecovery/AutoRecoverSapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

contract AutoRecoverSapientTest is Test {
  uint256 private constant SIGNER_PK = 0xA11CE;

  Allowlist internal allowlist;
  AutoRecoverSapient internal sapient;

  address internal signer;
  address internal wallet;
  address internal destination;

  function setUp() external {
    signer = vm.addr(SIGNER_PK);
    wallet = makeAddr("wallet");
    destination = makeAddr("destination");

    address[] memory initial = new address[](1);
    initial[0] = signer;

    allowlist = new Allowlist(address(this), initial);
    sapient = new AutoRecoverSapient(allowlist);
  }

  function test_recoverSapientSignature_reverts_invalidAllowSignatureLength() external {
    Payload.Decoded memory payload = _payload();
    bytes memory signature = abi.encode(destination, uint256(0), bytes(""));

    vm.prank(wallet);
    vm.expectRevert(
      abi.encodeWithSelector(AutoRecoverSapient.InvalidAllowSignatureLength.selector, uint256(0))
    );
    sapient.recoverSapientSignature(payload, signature);
  }

  function test_recoverSapientSignature_reverts_zeroRecoveredSigner() external {
    Payload.Decoded memory payload = _payload();
    bytes memory signature = abi.encode(destination, uint256(0), new bytes(64));

    vm.prank(wallet);
    vm.expectRevert(AutoRecoverSapient.InvalidRecoveredSigner.selector);
    sapient.recoverSapientSignature(payload, signature);
  }

  function test_recoverSapientSignature_returnsRoot_forAllowlistedSigner() external {
    Payload.Decoded memory payload = _payload();
    bytes memory signature = _signatureFor(payload);

    vm.prank(wallet);
    bytes32 got = sapient.recoverSapientSignature(payload, signature);

    assertEq(got, keccak256(abi.encode("auto-recover", destination, uint256(0))));
  }

  function test_recoverSapientSignature_reverts_invalidBehaviorOnError() external {
    Payload.Decoded memory payload = _payload();
    payload.calls[0].behaviorOnError = Payload.BEHAVIOR_IGNORE_ERROR;

    vm.prank(wallet);
    vm.expectRevert(
      abi.encodeWithSelector(
        AutoRecoverSapient.InvalidBehaviorOnError.selector, uint256(0), uint256(Payload.BEHAVIOR_IGNORE_ERROR)
      )
    );
    sapient.recoverSapientSignature(payload, _signatureFor(payload));
  }

  function test_recoverSapientSignature_reverts_delegateCallNotAllowed() external {
    Payload.Decoded memory payload = _payload();
    payload.calls[0].delegateCall = true;

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(AutoRecoverSapient.DelegateCallNotAllowed.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload));
  }

  function test_recoverSapientSignature_reverts_onlyFallbackNotAllowed() external {
    Payload.Decoded memory payload = _payload();
    payload.calls[0].onlyFallback = true;

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(AutoRecoverSapient.OnlyFallbackNotAllowed.selector, uint256(0)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload));
  }

  function test_recoverSapientSignature_reverts_gasLimitNotZero() external {
    Payload.Decoded memory payload = _payload();
    payload.calls[0].gasLimit = 1;

    vm.prank(wallet);
    vm.expectRevert(abi.encodeWithSelector(AutoRecoverSapient.GasLimitNotZero.selector, uint256(0), uint256(1)));
    sapient.recoverSapientSignature(payload, _signatureFor(payload));
  }

  function test_recoverSapientSignature_reverts_nativeTransferDataNotEmpty() external {
    Payload.Decoded memory payload = _payload();
    payload.calls[0].to = destination;
    payload.calls[0].value = 1;
    payload.calls[0].data = hex"deadbeef";

    vm.prank(wallet);
    vm.expectRevert(
      abi.encodeWithSelector(AutoRecoverSapient.NativeTransferDataNotEmpty.selector, uint256(0), uint256(4))
    );
    sapient.recoverSapientSignature(payload, _signatureFor(payload));
  }

  function _payload() private returns (Payload.Decoded memory payload) {
    payload.kind = Payload.KIND_TRANSACTIONS;
    payload.calls = new Payload.Call[](1);
    payload.calls[0] = Payload.Call({
      to: makeAddr("token"),
      value: 0,
      data: abi.encodeWithSelector(bytes4(0xa9059cbb), destination, uint256(123)),
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
    });
  }

  function _signatureFor(Payload.Decoded memory payload) private returns (bytes memory) {
    bytes32 payloadHash = Payload.hashFor(payload, wallet);
    bytes memory allowSignature = _compactSignature(payloadHash, SIGNER_PK);
    return abi.encode(destination, uint256(0), allowSignature);
  }

  function _compactSignature(bytes32 digest, uint256 privateKey) private returns (bytes memory) {
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    bytes32 yParityAndS = bytes32((uint256(s) & ((uint256(1) << 255) - 1)) | (uint256(v - 27) << 255));
    return abi.encodePacked(r, yParityAndS);
  }
}
