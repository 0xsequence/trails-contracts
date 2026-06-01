// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {LzOftSapient, IStargatePool} from "src/modules/LzOftSapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

contract MockStargatePool {
  uint256 public amountReceivedLD;

  function setAmountReceivedLD(uint256 _amount) external {
    amountReceivedLD = _amount;
  }

  function quoteOFT(IStargatePool.SendParam calldata)
    external
    view
    returns (
      IStargatePool.OFTLimit memory limit,
      IStargatePool.OFTFeeDetail[] memory oftFeeDetails,
      IStargatePool.OFTReceipt memory receipt
    )
  {
    limit = IStargatePool.OFTLimit({minAmountLD: 0, maxAmountLD: type(uint256).max});
    oftFeeDetails = new IStargatePool.OFTFeeDetail[](0);
    receipt = IStargatePool.OFTReceipt({amountSentLD: 1_000_000, amountReceivedLD: amountReceivedLD});
  }
}

contract LzOftSapientTest is Test {
  LzOftSapient internal sapient;
  MockStargatePool internal mockPool;

  uint32 internal dstEid;
  bytes32 internal recipient;

  // send(SendParam,MessagingFee,address)
  bytes4 private constant SEND_SELECTOR = 0xc7c7f5b3;

  function setUp() external {
    mockPool = new MockStargatePool();
    mockPool.setAmountReceivedLD(990_000); // 1% pool fee

    dstEid = 30375; // Katana
    recipient = bytes32(uint256(uint160(makeAddr("recipient"))));

    sapient = new LzOftSapient();
  }

  function _encodeSendCalldata(
    uint32 _dstEid,
    bytes32 _to,
    uint256 amountLD,
    uint256 minAmountLD
  ) internal pure returns (bytes memory) {
    IStargatePool.SendParam memory sp = IStargatePool.SendParam({
      dstEid: _dstEid,
      to: _to,
      amountLD: amountLD,
      minAmountLD: minAmountLD,
      extraOptions: hex"",
      composeMsg: hex"",
      oftCmd: hex""
    });

    IStargatePool.OFTLimit memory fee = IStargatePool.OFTLimit({
      minAmountLD: 0.01 ether,
      maxAmountLD: 0
    });

    return abi.encodeWithSelector(SEND_SELECTOR, sp, fee, address(0xBEEF));
  }

  function _buildPayload(bytes memory calldata_) internal view returns (Payload.Decoded memory) {
    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(mockPool),
      value: 0.01 ether,
      data: calldata_,
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

  function _encodeSig() internal view returns (bytes memory) {
    return abi.encode(uint8(0), address(mockPool), dstEid, recipient);
  }

  // --- Happy path ---

  function test_validSend_returnsFixedImageHash() external view {
    bytes memory calldata_ = _encodeSendCalldata(dstEid, recipient, 1_000_000, 990_000);
    Payload.Decoded memory payload = _buildPayload(calldata_);

    bytes32 result = sapient.recoverSapientSignature(payload, _encodeSig());
    bytes32 expected = sapient.imageHash(address(mockPool), dstEid, recipient);
    assertEq(result, expected);
    assertTrue(result != bytes32(0));
  }

  function test_minAmountAboveQuote_passes() external view {
    bytes memory calldata_ = _encodeSendCalldata(dstEid, recipient, 1_000_000, 995_000);
    Payload.Decoded memory payload = _buildPayload(calldata_);

    bytes32 result = sapient.recoverSapientSignature(payload, _encodeSig());
    assertEq(result, sapient.imageHash(address(mockPool), dstEid, recipient));
  }

  function test_differentAmounts_returnSameImageHash() external view {
    bytes memory call1 = _encodeSendCalldata(dstEid, recipient, 1_000_000, 990_000);
    bytes memory call2 = _encodeSendCalldata(dstEid, recipient, 50_000_000, 990_000);

    bytes32 hash1 = sapient.recoverSapientSignature(_buildPayload(call1), _encodeSig());
    bytes32 hash2 = sapient.recoverSapientSignature(_buildPayload(call2), _encodeSig());

    assertEq(hash1, hash2, "image hash must be stable regardless of amount");
  }

  // --- Wrong pool ---

  function test_wrongPool_reverts() external {
    address wrongPool = makeAddr("wrongPool");
    bytes memory calldata_ = _encodeSendCalldata(dstEid, recipient, 1_000_000, 990_000);

    // Build payload targeting the wrong pool
    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: wrongPool,
      value: 0.01 ether,
      data: calldata_,
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
    });
    Payload.Decoded memory payload = Payload.Decoded({
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

    vm.expectRevert(
      abi.encodeWithSelector(LzOftSapient.InvalidPool.selector, wrongPool, address(mockPool))
    );
    sapient.recoverSapientSignature(payload, _encodeSig());
  }

  // --- Different pools produce different imageHashes ---

  function test_differentPools_differentImageHash() external view {
    address pool1 = address(0x1111);
    address pool2 = address(0x2222);
    uint32 eid = 30375;
    bytes32 rcpt = bytes32(uint256(1));
    assertTrue(
      sapient.imageHash(pool1, eid, rcpt) != sapient.imageHash(pool2, eid, rcpt)
    );
  }

  // --- minAmountLD below quote ---

  function test_minAmountBelowQuote_reverts() external {
    bytes memory calldata_ = _encodeSendCalldata(dstEid, recipient, 1_000_000, 989_999);
    Payload.Decoded memory payload = _buildPayload(calldata_);

    vm.expectRevert(
      abi.encodeWithSelector(LzOftSapient.MinAmountTooLow.selector, uint256(989_999), uint256(990_000))
    );
    sapient.recoverSapientSignature(payload, _encodeSig());
  }

  // --- Invalid dstEid ---

  function test_wrongDstEid_reverts() external {
    uint32 wrongEid = 30101;
    bytes memory calldata_ = _encodeSendCalldata(wrongEid, recipient, 1_000_000, 990_000);
    Payload.Decoded memory payload = _buildPayload(calldata_);

    vm.expectRevert(abi.encodeWithSelector(LzOftSapient.InvalidDstEid.selector, wrongEid, dstEid));
    sapient.recoverSapientSignature(payload, _encodeSig());
  }

  // --- Invalid recipient ---

  function test_wrongRecipient_reverts() external {
    bytes32 wrongRecipient = bytes32(uint256(uint160(makeAddr("attacker"))));
    bytes memory calldata_ = _encodeSendCalldata(dstEid, wrongRecipient, 1_000_000, 990_000);
    Payload.Decoded memory payload = _buildPayload(calldata_);

    vm.expectRevert(
      abi.encodeWithSelector(LzOftSapient.InvalidRecipient.selector, wrongRecipient, recipient)
    );
    sapient.recoverSapientSignature(payload, _encodeSig());
  }

  // --- Wrong selector ---

  function test_wrongSelector_reverts() external {
    bytes memory calldata_ = abi.encodeWithSelector(bytes4(0xdeadbeef), uint256(1));
    Payload.Decoded memory payload = _buildPayload(calldata_);

    vm.expectRevert(
      abi.encodeWithSelector(LzOftSapient.InvalidSelector.selector, bytes4(0xdeadbeef))
    );
    sapient.recoverSapientSignature(payload, _encodeSig());
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

    vm.expectRevert(LzOftSapient.NonTransactionPayload.selector);
    sapient.recoverSapientSignature(payload, _encodeSig());
  }

  // --- imageHash ---

  function test_imageHash_deterministic() external view {
    assertEq(
      sapient.imageHash(address(mockPool), dstEid, recipient),
      sapient.imageHash(address(mockPool), dstEid, recipient)
    );
  }

  function test_imageHash_differentEid_differentHash() external view {
    assertTrue(
      sapient.imageHash(address(mockPool), 30375, recipient) !=
      sapient.imageHash(address(mockPool), 30101, recipient)
    );
  }
}
