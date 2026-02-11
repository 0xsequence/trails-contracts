// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";

import {HydrateProxy} from "src/modules/HydrateProxy.sol";
import {Sweepable} from "src/modules/Sweepable.sol";
import {Calls} from "wallet-contracts-v3/modules/Calls.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

import {PackedPayload} from "test/helpers/PackedPayload.sol";
import {MockERC20, RecordingReceiver, RevertingReceiver, RejectEther, Emitter} from "test/helpers/Mocks.sol";

contract HydrateProxyCaller {
  function hydrateExecute(HydrateProxy proxy, bytes calldata packedPayload, bytes calldata hydratePayload)
    external
    payable
  {
    proxy.hydrateExecute{value: msg.value}(packedPayload, hydratePayload);
  }

  function hydrateExecuteAndSweep(
    HydrateProxy proxy,
    bytes calldata packedPayload,
    address sweepTarget,
    address[] calldata tokensToSweep,
    bool sweepNative,
    bytes calldata hydratePayload
  ) external payable {
    proxy.hydrateExecuteAndSweep{value: msg.value}(
      packedPayload, hydratePayload, sweepTarget, tokensToSweep, sweepNative
    );
  }

  function delegateHydrateExecute(HydrateProxy proxy, bytes calldata packedPayload, bytes calldata hydratePayload)
    external
    payable
    returns (bool ok)
  {
    bytes memory data = abi.encodeWithSelector(HydrateProxy.hydrateExecute.selector, packedPayload, hydratePayload);
    (ok,) = address(proxy).delegatecall(data);
  }

  function handleSequenceDelegateCall(
    HydrateProxy proxy,
    bytes32 opHash,
    uint256 startingGas,
    uint256 index,
    uint256 numCalls,
    uint256 space,
    bytes calldata data
  ) external payable returns (bool ok) {
    bytes memory callData = abi.encodeWithSelector(
      HydrateProxy.handleSequenceDelegateCall.selector, opHash, startingGas, index, numCalls, space, data
    );
    (ok,) = address(proxy).delegatecall(callData);
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
    // 16 allowance values: 4 owners × 4 spenders
    // Row 0: Owner = SELF (proxy)
    uint128 proxyToProxyAllowance;
    uint128 proxyToCallerAllowance;
    uint128 proxyToOriginAllowance;
    uint128 proxyToSpenderAllowance;
    // Row 1: Owner = MESSAGE_SENDER (caller)
    uint128 callerToProxyAllowance;
    uint128 callerToCallerAllowance;
    uint128 callerToOriginAllowance;
    uint128 callerToSpenderAllowance;
    // Row 2: Owner = TRANSACTION_ORIGIN (originReceiver)
    uint128 originToProxyAllowance;
    uint128 originToCallerAllowance;
    uint128 originToOriginAllowance;
    uint128 originToSpenderAllowance;
    // Row 3: Owner = ANY_ADDRESS (anyAddr)
    uint128 anyToProxyAllowance;
    uint128 anyToCallerAllowance;
    uint128 anyToOriginAllowance;
    uint128 anyToSpenderAllowance;
    address spenderAddr;
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

  function _seededAmount(bytes32 seed, string memory prefix) private pure returns (uint128 amount) {
    uint256 tmp = uint256(keccak256(abi.encodePacked(seed, prefix)));
    amount = uint128(bound(tmp, 0, 1_000_000 ether));
  }

  function _hydrateAllFlagsCase(bytes32 seed) private pure returns (HydrateAllFlagsCase memory c) {
    c.anyAddr = address(uint160(uint256(keccak256(abi.encodePacked(seed, "any")))));
    vm.assume(c.anyAddr != address(0));

    c.msgValue = uint96(bound(_seededAmount(seed, "msgValue"), 0, 10 ether));
    c.callerEthBalance = uint96(bound(uint256(_seededAmount(seed, "callerEthBalance")), 0, 10 ether));
    c.originEthBalance = uint96(bound(uint256(_seededAmount(seed, "originEthBalance")), 0, 10 ether));
    c.anyEthBalance = uint96(bound(uint256(_seededAmount(seed, "anyEthBalance")), 0, 10 ether));

    c.proxyTokenBalance = _seededAmount(seed, "proxyTokenBalance");
    c.callerTokenBalance = _seededAmount(seed, "callerTokenBalance");
    c.originTokenBalance = _seededAmount(seed, "originTokenBalance");
    c.anyTokenBalance = _seededAmount(seed, "anyTokenBalance");

    c.spenderAddr = address(uint160(uint256(keccak256(abi.encodePacked(seed, "spender")))));
    vm.assume(c.spenderAddr != address(0));

    // Generate 16 allowance values (4 owners × 4 spenders)
    // Row 0: Owner = SELF (proxy)
    c.proxyToProxyAllowance = _seededAmount(seed, "proxyToProxy");
    c.proxyToCallerAllowance = _seededAmount(seed, "proxyToCaller");
    c.proxyToOriginAllowance = _seededAmount(seed, "proxyToOrigin");
    c.proxyToSpenderAllowance = _seededAmount(seed, "proxyToSpender");
    // Row 1: Owner = MESSAGE_SENDER (caller)
    c.callerToProxyAllowance = _seededAmount(seed, "callerToProxy");
    c.callerToCallerAllowance = _seededAmount(seed, "callerToCaller");
    c.callerToOriginAllowance = _seededAmount(seed, "callerToOrigin");
    c.callerToSpenderAllowance = _seededAmount(seed, "callerToSpender");
    // Row 2: Owner = TRANSACTION_ORIGIN (originReceiver)
    c.originToProxyAllowance = _seededAmount(seed, "originToProxy");
    c.originToCallerAllowance = _seededAmount(seed, "originToCaller");
    c.originToOriginAllowance = _seededAmount(seed, "originToOrigin");
    c.originToSpenderAllowance = _seededAmount(seed, "originToSpender");
    // Row 3: Owner = ANY_ADDRESS (anyAddr)
    c.anyToProxyAllowance = _seededAmount(seed, "anyToProxy");
    c.anyToCallerAllowance = _seededAmount(seed, "anyToCaller");
    c.anyToOriginAllowance = _seededAmount(seed, "anyToOrigin");
    c.anyToSpenderAllowance = _seededAmount(seed, "anyToSpender");
  }

  function _hydrateAllDataFlagsPayload(address anyAddr, address token, address spenderAddr)
    private
    pure
    returns (bytes memory hydratePayload)
  {
    // flag = (typeFlag << 4) | valueFlag
    // Type flags: DATA_ADDRESS=0x01, DATA_BALANCE=0x02, DATA_ERC20_BALANCE=0x03, DATA_ERC20_ALLOWANCE=0x04
    // Value flags: SELF=0x00, MESSAGE_SENDER=0x01, TRANSACTION_ORIGIN=0x02, ANY_ADDRESS=0x03

    hydratePayload = abi.encodePacked(uint8(0)); // Start with call index 0

    // HYDRATE_TYPE_DATA_ADDRESS (0x01) with all value flags
    // 0x10 = (0x01 << 4) | 0x00 = DATA_ADDRESS | SELF
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x10), uint16(0)));
    // 0x11 = (0x01 << 4) | 0x01 = DATA_ADDRESS | MESSAGE_SENDER
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x11), uint16(32)));
    // 0x12 = (0x01 << 4) | 0x02 = DATA_ADDRESS | TRANSACTION_ORIGIN
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x12), uint16(64)));
    // 0x13 = (0x01 << 4) | 0x03 = DATA_ADDRESS | ANY_ADDRESS
    // For ANY_ADDRESS, the address is read before cindex
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x13), anyAddr, uint16(96)));

    // HYDRATE_TYPE_DATA_BALANCE (0x02) with all value flags
    // 0x20 = (0x02 << 4) | 0x00 = DATA_BALANCE | SELF
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x20), uint16(128)));
    // 0x21 = (0x02 << 4) | 0x01 = DATA_BALANCE | MESSAGE_SENDER
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x21), uint16(160)));
    // 0x22 = (0x02 << 4) | 0x02 = DATA_BALANCE | TRANSACTION_ORIGIN
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x22), uint16(192)));
    // 0x23 = (0x02 << 4) | 0x03 = DATA_BALANCE | ANY_ADDRESS
    // For ANY_ADDRESS, the address is read before cindex
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x23), anyAddr, uint16(224)));

    // HYDRATE_TYPE_DATA_ERC20_BALANCE (0x03) with all value flags
    // 0x30 = (0x03 << 4) | 0x00 = DATA_ERC20_BALANCE | SELF
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x30), uint16(256), token));
    // 0x31 = (0x03 << 4) | 0x01 = DATA_ERC20_BALANCE | MESSAGE_SENDER
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x31), uint16(288), token));
    // 0x32 = (0x03 << 4) | 0x02 = DATA_ERC20_BALANCE | TRANSACTION_ORIGIN
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x32), uint16(320), token));
    // 0x33 = (0x03 << 4) | 0x03 = DATA_ERC20_BALANCE | ANY_ADDRESS
    // For valueFlag=ANY_ADDRESS, the owner address is read first (before cindex), then cindex, then token
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x33), anyAddr, uint16(352), token));

    // HYDRATE_TYPE_DATA_ERC20_ALLOWANCE (0x04) - Matrix of all owner � spender combinations (4�4 = 16)
    // Format: flag, [ownerAddr if ownerFlag is ANY_ADDRESS], cindex, token, spenderType, [spenderAddr if spenderType is ANY_ADDRESS]
    // Owner flags: SELF=0x00, MESSAGE_SENDER=0x01, TRANSACTION_ORIGIN=0x02, ANY_ADDRESS=0x03
    // Spender flags: SELF=0x00, MESSAGE_SENDER=0x01, TRANSACTION_ORIGIN=0x02, ANY_ADDRESS=0x03
    // Row 0: Owner = SELF (0x00)
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x40), uint16(384), token, uint8(0x00))); // Spender = SELF
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x40), uint16(416), token, uint8(0x01))); // Spender = MESSAGE_SENDER
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x40), uint16(448), token, uint8(0x02))); // Spender = TRANSACTION_ORIGIN
    hydratePayload =
      bytes.concat(hydratePayload, abi.encodePacked(uint8(0x40), uint16(480), token, uint8(0x03), spenderAddr)); // Spender = ANY_ADDRESS
    // Row 1: Owner = MESSAGE_SENDER (0x01)
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x41), uint16(512), token, uint8(0x00))); // Spender = SELF
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x41), uint16(544), token, uint8(0x01))); // Spender = MESSAGE_SENDER
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x41), uint16(576), token, uint8(0x02))); // Spender = TRANSACTION_ORIGIN
    hydratePayload =
      bytes.concat(hydratePayload, abi.encodePacked(uint8(0x41), uint16(608), token, uint8(0x03), spenderAddr)); // Spender = ANY_ADDRESS
    // Row 2: Owner = TRANSACTION_ORIGIN (0x02)
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x42), uint16(640), token, uint8(0x00))); // Spender = SELF
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x42), uint16(672), token, uint8(0x01))); // Spender = MESSAGE_SENDER
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x42), uint16(704), token, uint8(0x02))); // Spender = TRANSACTION_ORIGIN
    hydratePayload =
      bytes.concat(hydratePayload, abi.encodePacked(uint8(0x42), uint16(736), token, uint8(0x03), spenderAddr)); // Spender = ANY_ADDRESS
    // Row 3: Owner = ANY_ADDRESS (0x03)
    hydratePayload =
      bytes.concat(hydratePayload, abi.encodePacked(uint8(0x43), anyAddr, uint16(768), token, uint8(0x00))); // Spender = SELF
    hydratePayload =
      bytes.concat(hydratePayload, abi.encodePacked(uint8(0x43), anyAddr, uint16(800), token, uint8(0x01))); // Spender = MESSAGE_SENDER
    hydratePayload =
      bytes.concat(hydratePayload, abi.encodePacked(uint8(0x43), anyAddr, uint16(832), token, uint8(0x02))); // Spender = TRANSACTION_ORIGIN
    hydratePayload = bytes.concat(
      hydratePayload, abi.encodePacked(uint8(0x43), anyAddr, uint16(864), token, uint8(0x03), spenderAddr)
    ); // Spender = ANY_ADDRESS

    // End hydrate for call 0; next hydrate targets call 1; call 1 has an empty section.
    hydratePayload = bytes.concat(hydratePayload, abi.encodePacked(uint8(0x00), uint8(1), uint8(0x00)));
  }

  function testFuzz_hydrateExecute_hydratesAllDataFlags_andExecutes(bytes32 seed) external {
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

    // Set up allowances for all owner × spender combinations (16 total)
    // Row 0: Owner = SELF (proxy)
    vm.prank(address(proxy));
    token.approve(address(proxy), c.proxyToProxyAllowance); // Spender = SELF
    vm.prank(address(proxy));
    token.approve(address(caller), c.proxyToCallerAllowance); // Spender = MESSAGE_SENDER
    vm.prank(address(proxy));
    token.approve(address(originReceiver), c.proxyToOriginAllowance); // Spender = TRANSACTION_ORIGIN
    vm.prank(address(proxy));
    token.approve(c.spenderAddr, c.proxyToSpenderAllowance); // Spender = ANY_ADDRESS

    // Row 1: Owner = MESSAGE_SENDER (caller)
    vm.prank(address(caller));
    token.approve(address(proxy), c.callerToProxyAllowance); // Spender = SELF
    vm.prank(address(caller));
    token.approve(address(caller), c.callerToCallerAllowance); // Spender = MESSAGE_SENDER
    vm.prank(address(caller));
    token.approve(address(originReceiver), c.callerToOriginAllowance); // Spender = TRANSACTION_ORIGIN
    vm.prank(address(caller));
    token.approve(c.spenderAddr, c.callerToSpenderAllowance); // Spender = ANY_ADDRESS

    // Row 2: Owner = TRANSACTION_ORIGIN (originReceiver)
    vm.prank(address(originReceiver));
    token.approve(address(proxy), c.originToProxyAllowance); // Spender = SELF
    vm.prank(address(originReceiver));
    token.approve(address(caller), c.originToCallerAllowance); // Spender = MESSAGE_SENDER
    vm.prank(address(originReceiver));
    token.approve(address(originReceiver), c.originToOriginAllowance); // Spender = TRANSACTION_ORIGIN
    vm.prank(address(originReceiver));
    token.approve(c.spenderAddr, c.originToSpenderAllowance); // Spender = ANY_ADDRESS

    // Row 3: Owner = ANY_ADDRESS (anyAddr)
    vm.prank(c.anyAddr);
    token.approve(address(proxy), c.anyToProxyAllowance); // Spender = SELF
    vm.prank(c.anyAddr);
    token.approve(address(caller), c.anyToCallerAllowance); // Spender = MESSAGE_SENDER
    vm.prank(c.anyAddr);
    token.approve(address(originReceiver), c.anyToOriginAllowance); // Spender = TRANSACTION_ORIGIN
    vm.prank(c.anyAddr);
    token.approve(c.spenderAddr, c.anyToSpenderAllowance); // Spender = ANY_ADDRESS

    Payload.Call[] memory calls = new Payload.Call[](2);
    calls[0] = Payload.Call({
      to: address(msgSenderReceiver),
      value: 0,
      data: new bytes(896),
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });
    // Use a different receiver for call[1] so we can check call[0]'s data via lastData()
    RecordingReceiver otherReceiver = new RecordingReceiver();
    calls[1] = Payload.Call({
      to: address(otherReceiver),
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
    // Force tx.origin to be `originReceiver` for TRANSACTION_ORIGIN hydration.
    vm.prank(outerSender, address(originReceiver));
    caller.hydrateExecute{value: c.msgValue}(
      proxy, packed, _hydrateAllDataFlagsPayload(c.anyAddr, address(token), c.spenderAddr)
    );

    // The call should go to msgSenderReceiver (the original to address) since we're not testing TO hydration here
    bytes memory got = msgSenderReceiver.lastData();

    // DATA_ADDRESS commands (offsets 0, 32, 64, 96)
    assertEq(_readAddress(got, 0), address(proxy)); // 0x10: DATA_ADDRESS | SELF
    assertEq(_readAddress(got, 32), address(caller)); // 0x11: DATA_ADDRESS | MESSAGE_SENDER
    assertEq(_readAddress(got, 64), address(originReceiver)); // 0x12: DATA_ADDRESS | TRANSACTION_ORIGIN
    assertEq(_readAddress(got, 96), c.anyAddr); // 0x13: DATA_ADDRESS | ANY_ADDRESS

    // DATA_BALANCE commands (offsets 128, 160, 192, 224)
    assertEq(_readUint256(got, 128), c.msgValue); // 0x20: DATA_BALANCE | SELF (proxy's balance at hydration = msgValue)
    assertEq(_readUint256(got, 160), c.callerEthBalance); // 0x21: DATA_BALANCE | MESSAGE_SENDER
    assertEq(_readUint256(got, 192), c.originEthBalance); // 0x22: DATA_BALANCE | TRANSACTION_ORIGIN
    assertEq(_readUint256(got, 224), c.anyEthBalance); // 0x23: DATA_BALANCE | ANY_ADDRESS

    // DATA_ERC20_BALANCE commands (offsets 256, 288, 320, 352)
    assertEq(_readUint256(got, 256), uint256(c.proxyTokenBalance)); // 0x30: DATA_ERC20_BALANCE | SELF
    assertEq(_readUint256(got, 288), uint256(c.callerTokenBalance)); // 0x31: DATA_ERC20_BALANCE | MESSAGE_SENDER
    assertEq(_readUint256(got, 320), uint256(c.originTokenBalance)); // 0x32: DATA_ERC20_BALANCE | TRANSACTION_ORIGIN
    assertEq(_readUint256(got, 352), uint256(c.anyTokenBalance)); // 0x33: DATA_ERC20_BALANCE | ANY_ADDRESS

    // DATA_ERC20_ALLOWANCE commands - Matrix of all owner � spender combinations (4�4 = 16)
    // Owner types: SELF (proxy), MESSAGE_SENDER (caller), TRANSACTION_ORIGIN (originReceiver), ANY_ADDRESS (anyAddr)
    // Spender types: SELF (proxy), MESSAGE_SENDER (caller), TRANSACTION_ORIGIN (originReceiver), ANY_ADDRESS (spenderAddr)
    uint256 offset = 384;
    // Row 0: Owner = SELF (proxy)
    assertEq(_readUint256(got, offset), uint256(c.proxyToProxyAllowance)); // Spender = SELF
    offset += 32;
    assertEq(_readUint256(got, offset), uint256(c.proxyToCallerAllowance)); // Spender = MESSAGE_SENDER
    offset += 32;
    assertEq(_readUint256(got, offset), uint256(c.proxyToOriginAllowance)); // Spender = TRANSACTION_ORIGIN
    offset += 32;
    assertEq(_readUint256(got, offset), uint256(c.proxyToSpenderAllowance)); // Spender = ANY_ADDRESS
    offset += 32;
    // Row 1: Owner = MESSAGE_SENDER (caller)
    assertEq(_readUint256(got, offset), uint256(c.callerToProxyAllowance)); // Spender = SELF
    offset += 32;
    assertEq(_readUint256(got, offset), uint256(c.callerToCallerAllowance)); // Spender = MESSAGE_SENDER
    offset += 32;
    assertEq(_readUint256(got, offset), uint256(c.callerToOriginAllowance)); // Spender = TRANSACTION_ORIGIN
    offset += 32;
    assertEq(_readUint256(got, offset), uint256(c.callerToSpenderAllowance)); // Spender = ANY_ADDRESS
    offset += 32;
    // Row 2: Owner = TRANSACTION_ORIGIN (originReceiver)
    assertEq(_readUint256(got, offset), uint256(c.originToProxyAllowance)); // Spender = SELF
    offset += 32;
    assertEq(_readUint256(got, offset), uint256(c.originToCallerAllowance)); // Spender = MESSAGE_SENDER
    offset += 32;
    assertEq(_readUint256(got, offset), uint256(c.originToOriginAllowance)); // Spender = TRANSACTION_ORIGIN
    offset += 32;
    assertEq(_readUint256(got, offset), uint256(c.originToSpenderAllowance)); // Spender = ANY_ADDRESS
    offset += 32;
    // Row 3: Owner = ANY_ADDRESS (anyAddr)
    assertEq(_readUint256(got, offset), uint256(c.anyToProxyAllowance)); // Spender = SELF
    offset += 32;
    assertEq(_readUint256(got, offset), uint256(c.anyToCallerAllowance)); // Spender = MESSAGE_SENDER
    offset += 32;
    assertEq(_readUint256(got, offset), uint256(c.anyToOriginAllowance)); // Spender = TRANSACTION_ORIGIN
    offset += 32;
    assertEq(_readUint256(got, offset), uint256(c.anyToSpenderAllowance)); // Spender = ANY_ADDRESS
    offset += 32;

    // Unchanged data for call[1]
    got = otherReceiver.lastData();
    assertEq(got, hex"deadbeef");
  }

  function test_hydrateExecute_hydrateTo_SELF_setsToProxy() external {
    HydrateProxy proxy = new HydrateProxy();
    RecordingReceiver initialReceiver = new RecordingReceiver();

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(initialReceiver),
      value: 0,
      data: hex"deadbeef",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    // 0x50 = (0x05 << 4) | 0x00 = TO | SELF
    bytes memory hydratePayload = abi.encodePacked(uint8(0), uint8(0x50), uint8(0x00));

    proxy.hydrateExecute(calls.packCalls(), hydratePayload);
    // The call should NOT go to initialReceiver since TO hydration changed it to the proxy
    // Note: The proxy itself doesn't have a fallback, so the call will fail silently
    // This test mainly verifies the hydration doesn't crash
    assertEq(initialReceiver.calls(), 0);
  }

  function test_hydrateExecute_hydrateTo_MESSAGE_SENDER_setsToCaller() external {
    HydrateProxy proxy = new HydrateProxy();
    HydrateProxyCaller caller = new HydrateProxyCaller();
    RecordingReceiver initialReceiver = new RecordingReceiver();

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(initialReceiver),
      value: 0,
      data: hex"deadbeef",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    // 0x51 = (0x05 << 4) | 0x01 = TO | MESSAGE_SENDER
    bytes memory hydratePayload = abi.encodePacked(uint8(0), uint8(0x51), uint8(0x00));

    caller.hydrateExecute(proxy, calls.packCalls(), hydratePayload);
    // The call should NOT go to initialReceiver since TO hydration changed it to the caller
    // The caller doesn't have a fallback, so the call will fail
    // This test mainly verifies the hydration doesn't crash
    assertEq(initialReceiver.calls(), 0);
  }

  function test_hydrateExecute_hydrateTo_TRANSACTION_ORIGIN_setsToOrigin() external {
    HydrateProxy proxy = new HydrateProxy();
    HydrateProxyCaller caller = new HydrateProxyCaller();
    RecordingReceiver initialReceiver = new RecordingReceiver();
    RecordingReceiver originReceiver = new RecordingReceiver();

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(initialReceiver),
      value: 0,
      data: hex"deadbeef",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    // 0x52 = (0x05 << 4) | 0x02 = TO | TRANSACTION_ORIGIN
    bytes memory hydratePayload = abi.encodePacked(uint8(0), uint8(0x52), uint8(0x00));

    address outerSender = makeAddr("outer-sender");
    vm.prank(outerSender, address(originReceiver));
    caller.hydrateExecute(proxy, calls.packCalls(), hydratePayload);
    assertEq(originReceiver.calls(), 1); // Should receive the call
    assertEq(initialReceiver.calls(), 0); // Should NOT receive the call
  }

  function test_hydrateExecute_hydrateTo_ANY_ADDRESS_setsToProvidedAddress() external {
    HydrateProxy proxy = new HydrateProxy();
    RecordingReceiver initialReceiver = new RecordingReceiver();
    RecordingReceiver targetReceiver = new RecordingReceiver();

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(initialReceiver),
      value: 0,
      data: hex"deadbeef",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    // 0x53 = (0x05 << 4) | 0x03 = TO | ANY_ADDRESS
    bytes memory hydratePayload = abi.encodePacked(uint8(0), uint8(0x53), address(targetReceiver), uint8(0x00));

    proxy.hydrateExecute(calls.packCalls(), hydratePayload);
    assertEq(targetReceiver.calls(), 1); // Should receive the call
    assertEq(initialReceiver.calls(), 0); // Should NOT receive the call
  }

  function test_hydrateExecute_hydrateValue_SELF_setsToProxyBalance() external {
    uint96 msgValue = 5 ether;
    HydrateProxy proxy = new HydrateProxy();
    RecordingReceiver receiver = new RecordingReceiver();

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(receiver),
      value: 0,
      data: hex"deadbeef",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    // 0x60 = (0x06 << 4) | 0x00 = VALUE | SELF
    bytes memory hydratePayload = abi.encodePacked(uint8(0), uint8(0x60), uint8(0x00));

    proxy.hydrateExecute{value: msgValue}(calls.packCalls(), hydratePayload);
    assertEq(receiver.lastValue(), msgValue); // Should receive the proxy's balance (msgValue)
  }

  function test_hydrateExecute_hydrateValue_MESSAGE_SENDER_setsToCallerBalance() external {
    uint96 callerBalance = 3 ether;
    HydrateProxy proxy = new HydrateProxy();
    HydrateProxyCaller caller = new HydrateProxyCaller();
    RecordingReceiver receiver = new RecordingReceiver();

    vm.deal(address(caller), callerBalance);
    // The proxy needs to have the ETH to send it in the call
    vm.deal(address(proxy), callerBalance);

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(receiver),
      value: 0,
      data: hex"deadbeef",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    // 0x61 = (0x06 << 4) | 0x01 = VALUE | MESSAGE_SENDER
    bytes memory hydratePayload = abi.encodePacked(uint8(0), uint8(0x61), uint8(0x00));

    caller.hydrateExecute(proxy, calls.packCalls(), hydratePayload);
    assertEq(receiver.lastValue(), callerBalance); // Should receive the caller's balance
  }

  function test_hydrateExecute_hydrateValue_TRANSACTION_ORIGIN_setsToOriginBalance() external {
    uint96 originBalance = 7 ether;
    HydrateProxy proxy = new HydrateProxy();
    HydrateProxyCaller caller = new HydrateProxyCaller();
    RecordingReceiver originReceiver = new RecordingReceiver();

    vm.deal(address(originReceiver), originBalance);
    // The proxy needs to have the ETH to send it in the call
    vm.deal(address(proxy), originBalance);

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(originReceiver),
      value: 0,
      data: hex"deadbeef",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    // 0x62 = (0x06 << 4) | 0x02 = VALUE | TRANSACTION_ORIGIN
    bytes memory hydratePayload = abi.encodePacked(uint8(0), uint8(0x62), uint8(0x00));

    address outerSender = makeAddr("outer-sender");
    vm.prank(outerSender, address(originReceiver));
    caller.hydrateExecute(proxy, calls.packCalls(), hydratePayload);
    assertEq(originReceiver.lastValue(), originBalance); // Should receive the origin's balance
  }

  function test_hydrateExecute_hydrateValue_ANY_ADDRESS_setsToProvidedBalance() external {
    uint96 anyBalance = 2 ether;
    address anyAddr = makeAddr("any-addr");
    HydrateProxy proxy = new HydrateProxy();
    RecordingReceiver receiver = new RecordingReceiver();

    vm.deal(anyAddr, anyBalance);
    // The proxy needs to have the ETH to send it in the call
    vm.deal(address(proxy), anyBalance);

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(receiver),
      value: 0,
      data: hex"deadbeef",
      gasLimit: 0,
      delegateCall: false,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    // 0x63 = (0x06 << 4) | 0x03 = VALUE | ANY_ADDRESS
    bytes memory hydratePayload = abi.encodePacked(uint8(0), uint8(0x63), anyAddr, uint8(0x00));

    proxy.hydrateExecute(calls.packCalls(), hydratePayload);
    assertEq(receiver.lastValue(), anyBalance); // Should receive the anyAddr's balance
  }

  function testFuzz_hydrateExecute_emptyHydratePayload_executes(bytes4 marker) external {
    vm.assume(
      marker != SELECTOR_CALLS && marker != SELECTOR_RESET && marker != SELECTOR_LAST_DATA
        && marker != SELECTOR_LAST_VALUE && marker != SELECTOR_LAST_SENDER
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
    // With nibble-based encoding, valid flags are 0x00-0x63
    // Test invalid flags: either invalid value flag (bottom nibble > 0x03) or invalid type flag (top nibble > 0x06)
    uint8 valueFlag = flag & 0x0F;
    uint8 typeFlag = flag >> 4;

    // Skip valid flags (0x00-0x63)
    vm.assume(flag > 0x63 || (valueFlag > 0x03) || (typeFlag > 0x06 && valueFlag <= 0x03));

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

    // If value flag is invalid, expect UnknownHydrateDataCommand with valueFlag
    // Otherwise, expect UnknownHydrateTypeCommand with typeFlag
    if (valueFlag > 0x03) {
      vm.expectRevert(abi.encodeWithSelector(HydrateProxy.UnknownHydrateDataCommand.selector, uint256(valueFlag)));
    } else {
      vm.expectRevert(abi.encodeWithSelector(HydrateProxy.UnknownHydrateTypeCommand.selector, uint256(typeFlag)));
    }
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

  function testFuzz_hydrateExecute_delegateCallAllowedInCallerContext_execute(bytes calldata data) external {
    HydrateProxy proxy = new HydrateProxy();
    HydrateProxyCaller caller = new HydrateProxyCaller();
    Emitter emitter = new Emitter();

    vm.assume(data.length <= 64);

    bytes memory emitterData = abi.encodeWithSelector(Emitter.doEmit.selector, data);

    Payload.Call[] memory calls = new Payload.Call[](1);
    calls[0] = Payload.Call({
      to: address(emitter),
      value: 0,
      data: emitterData,
      gasLimit: 0,
      delegateCall: true,
      onlyFallback: false,
      behaviorOnError: Payload.BEHAVIOR_IGNORE_ERROR
    });

    vm.expectEmit(true, true, true, true, address(caller));
    emit Emitter.Emitted(address(this), data, 0);
    bool ok = caller.delegateHydrateExecute(proxy, calls.packCalls(), "");
    assertTrue(ok);
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

  function testFuzz_hydrateExecute_behavior3_fallthrough_emitsSucceeded(bytes calldata data, bytes4 afterData)
    external
  {
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
    proxy.hydrateExecuteAndSweep{value: msgValue}(calls.packCalls(), "", address(0), tokens, true);

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

    proxy.hydrateExecuteAndSweep(calls.packCalls(), "", sweepTarget, tokens, true);
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

    vm.expectRevert(Sweepable.NativeSweepFailed.selector);
    proxy.hydrateExecuteAndSweep{value: msgValue}(calls.packCalls(), "", address(rejector), tokens, true);
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
      marker != SELECTOR_CALLS && marker != SELECTOR_RESET && marker != SELECTOR_LAST_DATA
        && marker != SELECTOR_LAST_VALUE && marker != SELECTOR_LAST_SENDER
    );

    HydrateProxy proxy = new HydrateProxy();
    HydrateProxyCaller caller = new HydrateProxyCaller();
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
    // The data parameter should be the full calldata to call hydrateExecute,
    // including the function selector, which will be passed to SELF.delegatecall(data)
    // inside handleSequenceDelegateCall
    bytes memory data = abi.encodeWithSelector(HydrateProxy.hydrateExecute.selector, packed, bytes(""));

    // Call via delegatecall to simulate Sequence wallet behavior
    // When called via delegatecall, address(this) inside handleSequenceDelegateCall will be
    // the caller contract's address (not SELF), so the check passes
    bool ok = caller.handleSequenceDelegateCall(proxy, bytes32(0), 0, 0, 0, 0, data);
    assertTrue(ok);
    assertEq(receiver.calls(), 1);
  }
}
