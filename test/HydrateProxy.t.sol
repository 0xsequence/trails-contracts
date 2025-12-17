// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {HydrateProxy} from "src/modules/HydrateProxy.sol";
import {Sweep} from "src/modules/Sweep.sol";
import {Calls} from "wallet-contracts-v3/modules/Calls.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

import {PackedPayload} from "test/helpers/PackedPayload.sol";
import {MockERC20, RecordingReceiver, RevertingReceiver, RejectEther} from "test/helpers/Mocks.sol";

contract HydrateProxyCaller {
  function hydrateExecute(HydrateProxy proxy, bytes calldata packedPayload, bytes calldata hydratePayload) external payable {
    proxy.hydrateExecute{value: msg.value}(packedPayload, hydratePayload);
  }

  function hydrateExecuteAndSweep(
    HydrateProxy proxy,
    bytes calldata packedPayload,
    address sweepTarget,
    address[] calldata tokensToSweep,
    bytes calldata hydratePayload
  ) external payable {
    proxy.hydrateExecuteAndSweep{value: msg.value}(packedPayload, sweepTarget, tokensToSweep, hydratePayload);
  }
}

contract HydrateProxyTest is Test {
  using PackedPayload for Payload.Call[];

  struct HydrateAllFlagsCase {
    address anyAddr;
    uint96 msgValue;
    uint96 callerEthBalance;
    uint96 originEthBalance;
    uint96 anyEthBalance;
    uint128 proxyTokenBalance;
    uint128 callerTokenBalance;
    uint128 originTokenBalance;
    uint128 anyTokenBalance;
  }

  bytes4 private constant SELECTOR_CALLS = bytes4(keccak256("calls()"));
  bytes4 private constant SELECTOR_RESET = bytes4(keccak256("reset()"));
  bytes4 private constant SELECTOR_LAST_DATA = bytes4(keccak256("lastData()"));
  bytes4 private constant SELECTOR_LAST_VALUE = bytes4(keccak256("lastValue()"));
  bytes4 private constant SELECTOR_LAST_SENDER = bytes4(keccak256("lastSender()"));

  function _readAddress(bytes memory data, uint256 offset) private pure returns (address a) {
    assembly ("memory-safe") {
      a := shr(96, mload(add(add(data, 32), offset)))
    }
  }

  function _readUint256(bytes memory data, uint256 offset) private pure returns (uint256 v) {
    assembly ("memory-safe") {
      v := mload(add(add(data, 32), offset))
    }
  }

  function _selector(bytes memory revertData) private pure returns (bytes4 sel) {
    if (revertData.length < 4) return bytes4(0);
    assembly ("memory-safe") {
      sel := mload(add(revertData, 32))
    }
  }

  function _hydrateAllFlagsCase(bytes32 seed) private pure returns (HydrateAllFlagsCase memory c) {
    c.anyAddr = address(uint160(uint256(keccak256(abi.encodePacked(seed, "any")))));
    vm.assume(c.anyAddr != address(0));

    c.msgValue = uint96(bound(uint256(keccak256(abi.encodePacked(seed, "msgValue"))), 0, 10 ether));
    c.callerEthBalance = uint96(bound(uint256(keccak256(abi.encodePacked(seed, "callerEthBalance"))), 0, 10 ether));
    c.originEthBalance = uint96(bound(uint256(keccak256(abi.encodePacked(seed, "originEthBalance"))), 0, 10 ether));
    c.anyEthBalance = uint96(bound(uint256(keccak256(abi.encodePacked(seed, "anyEthBalance"))), 0, 10 ether));

    c.proxyTokenBalance =
      uint128(bound(uint256(keccak256(abi.encodePacked(seed, "proxyTokenBalance"))), 0, 1_000_000 ether));
    c.callerTokenBalance =
      uint128(bound(uint256(keccak256(abi.encodePacked(seed, "callerTokenBalance"))), 0, 1_000_000 ether));
    c.originTokenBalance =
      uint128(bound(uint256(keccak256(abi.encodePacked(seed, "originTokenBalance"))), 0, 1_000_000 ether));
    c.anyTokenBalance =
      uint128(bound(uint256(keccak256(abi.encodePacked(seed, "anyTokenBalance"))), 0, 1_000_000 ether));
  }

  function _hydrateAllFlagsPayload(
    address anyAddr,
    address token
  ) private pure returns (bytes memory hydratePayload) {
    hydratePayload = abi.encodePacked(uint8(0));

    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x01), uint16(0)));
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x02), uint16(32)));
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x03), uint16(64)));

    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x04), uint16(96)));
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x05), uint16(128)));
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x06), uint16(160)));
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x07), uint16(192), anyAddr));

    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x08), uint16(224), token));
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x09), uint16(256), token));
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x0A), uint16(288), token));
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x0B), uint16(320), token, anyAddr));

    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x0C), uint8(0x0D), uint8(0x0E)));

    // End hydrate for call 0; next hydrate targets call 1; call 1 has an empty section.
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x00), uint8(1), uint8(0x00)));
  }

  function testFuzz_hydrateExecute_hydratesAllFlags_andExecutes(bytes32 seed) external {
    HydrateProxy proxy = new HydrateProxy();
    HydrateProxyCaller caller = new HydrateProxyCaller();

    RecordingReceiver msgSenderReceiver = new RecordingReceiver();
    RecordingReceiver originReceiver = new RecordingReceiver();

    MockERC20 token = new MockERC20();

    HydrateAllFlagsCase memory c = _hydrateAllFlagsCase(seed);

    vm.deal(address(caller), c.callerEthBalance);
    vm.deal(address(originReceiver), c.originEthBalance);
    vm.deal(c.anyAddr, c.anyEthBalance);

    token.mint(address(proxy), c.proxyTokenBalance);
    token.mint(address(caller), c.callerTokenBalance);
    token.mint(address(originReceiver), c.originTokenBalance);
    token.mint(c.anyAddr, c.anyTokenBalance);

    Payload.Call[] memory calls = new Payload.Call[](2);
    calls[0] = Payload.Call({
      to: address(msgSenderReceiver),
      value: 0,
      data: new bytes(400),
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });
    calls[1] = Payload.Call({
      to: address(msgSenderReceiver),
      value: 0,
      data: hex"deadbeef",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    bytes memory packed = calls.packCalls();

    // Fund the EOA that triggers the call (pays `msg.value` into the proxy).
    address outerSender = makeAddr("outer-sender");
    vm.deal(outerSender, uint256(c.msgValue) + 1 ether);

    // Call via a contract so `msg.sender` inside the proxy is a contract address.
    // Force tx.origin to be `originReceiver` to cover HYDRATE_TO_TRANSACTION_ORIGIN_ADDRESS.
    vm.prank(outerSender, address(originReceiver));
    caller.hydrateExecute{value: c.msgValue}(proxy, packed, _hydrateAllFlagsPayload(c.anyAddr, address(token)));

    bytes memory got = originReceiver.lastData();

    assertEq(_readAddress(got, 0), address(proxy));
    assertEq(_readAddress(got, 32), address(caller));
    assertEq(_readAddress(got, 64), address(originReceiver));

    assertEq(_readUint256(got, 96), c.msgValue);
    assertEq(_readUint256(got, 128), c.callerEthBalance);
    assertEq(_readUint256(got, 160), c.originEthBalance);
    assertEq(_readUint256(got, 192), c.anyEthBalance);

    assertEq(_readUint256(got, 224), uint256(c.proxyTokenBalance));
    assertEq(_readUint256(got, 256), uint256(c.callerTokenBalance));
    assertEq(_readUint256(got, 288), uint256(c.originTokenBalance));
    assertEq(_readUint256(got, 320), uint256(c.anyTokenBalance));

    // HYDRATE_AMOUNT_SELF_BALANCE sets call.value to the proxy's balance at hydration time.
    assertEq(originReceiver.lastValue(), c.msgValue);
  }

  function testFuzz_hydrateExecute_emptyHydratePayload_executes(bytes4 marker) external {
    vm.assume(
      marker != SELECTOR_CALLS && marker != SELECTOR_RESET && marker != SELECTOR_LAST_DATA && marker != SELECTOR_LAST_VALUE
        && marker != SELECTOR_LAST_SENDER
    );

    HydrateProxy proxy = new HydrateProxy();
    RecordingReceiver receiver = new RecordingReceiver();

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(receiver),
      value: 0,
      data: abi.encodePacked(marker),
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    proxy.hydrateExecute(calls.packCalls(), "");
    assertEq(receiver.calls(), 1);
  }

  function testFuzz_hydrateExecute_unknownHydrateFlag_reverts(uint8 flag) external {
    vm.assume(flag >= 0x0F);

    HydrateProxy proxy = new HydrateProxy();
    RecordingReceiver receiver = new RecordingReceiver();

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(receiver),
      value: 0,
      data: hex"01",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    bytes memory hydratePayload = bytes.concat(bytes1(uint8(0)), bytes1(flag));
    vm.expectRevert(abi.encodeWithSelector(HydrateProxy.UnknownHydrateDataCommand.selector, uint256(flag)));
    proxy.hydrateExecute(calls.packCalls(), hydratePayload);
  }

  function testFuzz_hydrateExecute_delegateCallNotAllowed_reverts(bytes calldata data) external {
    HydrateProxy proxy = new HydrateProxy();

    vm.assume(data.length <= 64);

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(new RecordingReceiver()),
      value: 0,
      data: data,
      gasLimit: 0,
      delegateCall: true,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    vm.expectRevert(abi.encodeWithSelector(HydrateProxy.DelegateCallNotAllowed.selector, uint256(0)));
    proxy.hydrateExecute(calls.packCalls(), "");
  }

  function testFuzz_hydrateExecute_notEnoughGas_reverts(uint256 delta) external {
    HydrateProxy proxy = new HydrateProxy();

    delta = bound(delta, 0, type(uint128).max);
    uint256 gasLimit = type(uint256).max - delta;
    vm.assume(gasLimit > 0);

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(new RecordingReceiver()),
      value: 0,
      data: hex"01",
      gasLimit: gasLimit,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    (bool ok, bytes memory revertData) =
      address(proxy).call(abi.encodeWithSelector(HydrateProxy.hydrateExecute.selector, calls.packCalls(), ""));
    assertFalse(ok);
    assertEq(_selector(revertData), Calls.NotEnoughGas.selector);
  }

  function testFuzz_hydrateExecute_ignoreError_enablesOnlyFallback(bytes4 dataA, bytes4 dataB, bytes4 dataD) external {
    vm.assume(
      dataB != SELECTOR_CALLS && dataB != SELECTOR_RESET && dataB != SELECTOR_LAST_DATA && dataB != SELECTOR_LAST_VALUE
        && dataB != SELECTOR_LAST_SENDER
    );
    vm.assume(
      dataD != SELECTOR_CALLS && dataD != SELECTOR_RESET && dataD != SELECTOR_LAST_DATA && dataD != SELECTOR_LAST_VALUE
        && dataD != SELECTOR_LAST_SENDER
    );

    HydrateProxy proxy = new HydrateProxy();

    RecordingReceiver recvA = new RecordingReceiver();
    RecordingReceiver recvB = new RecordingReceiver();
    RecordingReceiver recvC = new RecordingReceiver();
    RecordingReceiver recvD = new RecordingReceiver();
    RevertingReceiver reverter = new RevertingReceiver();

    Payload.Call[] memory calls = new Payload.Call[](5);
    // 0: onlyFallback skipped (no prior error)
    calls[0] = Payload.Call({
      to: address(recvA),
      value: 0,
      data: abi.encodePacked(dataA),
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: true,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });
    // 1: fails and is ignored => errorFlag=true for next call
    calls[1] = Payload.Call({
      to: address(reverter),
      value: 0,
      data: hex"02",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });
    // 2: onlyFallback executed due to errorFlag=true
    calls[2] = Payload.Call({
      to: address(recvB),
      value: 0,
      data: abi.encodePacked(dataB),
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: true,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });
    // 3: onlyFallback skipped (errorFlag reset after executing call 2)
    calls[3] = Payload.Call({
      to: address(recvC),
      value: 0,
      data: hex"03",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: true,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });
    // 4: normal call executes after ignore-error flow
    calls[4] = Payload.Call({
      to: address(recvD),
      value: 0,
      data: abi.encodePacked(dataD),
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    proxy.hydrateExecute(calls.packCalls(), "");

    assertEq(recvA.calls(), 0);
    assertEq(recvB.calls(), 1);
    assertEq(recvC.calls(), 0);
    assertEq(recvD.calls(), 1);
  }

  function testFuzz_hydrateExecute_revertOnError_reverts(bytes calldata data) external {
    HydrateProxy proxy = new HydrateProxy();

    vm.assume(data.length <= 64);
    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(new RevertingReceiver()),
      value: 0,
      data: data,
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
    });

    (bool ok, bytes memory revertData) =
      address(proxy).call(abi.encodeWithSelector(HydrateProxy.hydrateExecute.selector, calls.packCalls(), ""));
    assertFalse(ok);
    assertEq(_selector(revertData), Calls.Reverted.selector);
  }

  function testFuzz_hydrateExecute_abortOnError_aborts(bytes calldata data, bytes4 afterData) external {
    HydrateProxy proxy = new HydrateProxy();

    vm.assume(data.length <= 64);

    RecordingReceiver afterReceiver = new RecordingReceiver();
    Payload.Call[] memory calls = new Payload.Call[](2);
    calls[0] = Payload.Call({
      to: address(new RevertingReceiver()),
      value: 0,
      data: data,
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_ABORT_ON_ERROR
    });
    calls[1] = Payload.Call({
      to: address(afterReceiver),
      value: 0,
      data: abi.encodePacked(afterData),
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    proxy.hydrateExecute(calls.packCalls(), "");
    assertEq(afterReceiver.calls(), 0);
  }

  function testFuzz_hydrateExecute_behavior3_fallthrough_emitsSucceeded(bytes calldata data, bytes4 afterData) external {
    HydrateProxy proxy = new HydrateProxy();
    vm.assume(data.length <= 64);
    vm.assume(
      afterData != SELECTOR_CALLS && afterData != SELECTOR_RESET && afterData != SELECTOR_LAST_DATA
        && afterData != SELECTOR_LAST_VALUE && afterData != SELECTOR_LAST_SENDER
    );

    RecordingReceiver afterReceiver = new RecordingReceiver();
    Payload.Call[] memory calls = new Payload.Call[](2);
    calls[0] = Payload.Call({
      to: address(new RevertingReceiver()),
      value: 0,
      data: data,
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: 3
    });
    calls[1] = Payload.Call({
      to: address(afterReceiver),
      value: 0,
      data: abi.encodePacked(afterData),
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    // Should not revert or abort, even though call[0] fails.
    proxy.hydrateExecute(calls.packCalls(), "");
    assertEq(afterReceiver.calls(), 1);
  }

  function testFuzz_hydrateExecuteAndSweep_sweepsEthAndTokens_toMsgSenderWhenZeroTarget(
    uint96 msgValue,
    uint128 tokenAmount
  ) external {
    HydrateProxy proxy = new HydrateProxy();
    MockERC20 token = new MockERC20();
    RecordingReceiver receiver = new RecordingReceiver();

    msgValue = uint96(bound(msgValue, 0, 10 ether));
    tokenAmount = uint128(bound(tokenAmount, 0, 1_000_000 ether));
    token.mint(address(proxy), tokenAmount);

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(receiver),
      value: 0,
      data: hex"01",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    address sweepCaller = makeAddr("sweep-caller");
    vm.deal(sweepCaller, msgValue + 1 ether);

    address[] memory tokens = new address[](1);
    tokens[0] = address(token);

    uint256 sweepCallerEthBefore = sweepCaller.balance;

    vm.txGasPrice(0);
    vm.prank(sweepCaller);
    proxy.hydrateExecuteAndSweep{value: msgValue}(calls.packCalls(), address(0), tokens, "");

    assertEq(token.balanceOf(sweepCaller), tokenAmount);
    assertEq(sweepCaller.balance, sweepCallerEthBefore);
    assertEq(address(proxy).balance, 0);
  }

  function testFuzz_hydrateExecuteAndSweep_explicitTarget_andNoBalances(address sweepTarget) external {
    HydrateProxy proxy = new HydrateProxy();
    RecordingReceiver receiver = new RecordingReceiver();

    vm.assume(sweepTarget != address(0));

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(receiver),
      value: 0,
      data: hex"01",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    address[] memory tokens = new address[](0);

    proxy.hydrateExecuteAndSweep(calls.packCalls(), sweepTarget, tokens, "");
    assertEq(receiver.calls(), 1);
  }

  function testFuzz_hydrateExecuteAndSweep_revertsWhenEthSweepFails(uint96 msgValue) external {
    HydrateProxy proxy = new HydrateProxy();
    RejectEther rejector = new RejectEther();
    RecordingReceiver receiver = new RecordingReceiver();

    msgValue = uint96(bound(msgValue, 1, 10 ether));

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(receiver),
      value: 0,
      data: hex"01",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    address[] memory tokens = new address[](0);

    vm.expectRevert(Sweep.BalanceSweepFailed.selector);
    proxy.hydrateExecuteAndSweep{value: msgValue}(calls.packCalls(), address(rejector), tokens, "");
  }

  function testFuzz_receive_acceptsEth(uint96 amount) external {
    amount = uint96(bound(amount, 0, 10 ether));

    HydrateProxy proxy = new HydrateProxy();
    address sender = makeAddr("sender");
    vm.deal(sender, amount);

    vm.prank(sender);
    (bool ok,) = payable(address(proxy)).call{value: amount}("");
    assertTrue(ok);
  }

  function testFuzz_handleSequenceDelegateCall_decodesAndExecutes(bytes4 marker) external {
    vm.assume(
      marker != SELECTOR_CALLS && marker != SELECTOR_RESET && marker != SELECTOR_LAST_DATA && marker != SELECTOR_LAST_VALUE
        && marker != SELECTOR_LAST_SENDER
    );

    HydrateProxy proxy = new HydrateProxy();
    RecordingReceiver receiver = new RecordingReceiver();

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(receiver),
      value: 0,
      data: abi.encodePacked(marker),
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    bytes memory packed = calls.packCalls();
    bytes memory data = abi.encode(packed, bytes(""));

    proxy.handleSequenceDelegateCall(bytes32(0), 0, 0, 0, 0, data);
    assertEq(receiver.calls(), 1);
  }
}
