// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {TrailsRouterShim} from "../src/TrailsRouterShim.sol";
import {IDelegatedExtension} from "wallet-contracts-v3/modules/interfaces/IDelegatedExtension.sol";

contract TrailsRouterShimTest is Test {
    bytes32 internal constant SENTINEL_NAMESPACE = keccak256("org.sequence.trails.router.sentinel");
    bytes32 internal constant SENTINEL_VALUE = bytes32(uint256(1));

    MockRouter internal router;
    TrailsRouterShim internal shim;
    WalletHarness internal wallet;

    function setUp() public {
        router = new MockRouter();
        shim = new TrailsRouterShim(address(router));
        wallet = new WalletHarness();
    }

    function testExecuteForwardsAndSetsSentinel() public {
        bytes memory multicallData = abi.encode(uint256(123));
        bytes memory callData = abi.encodeWithSelector(MockRouter.execute.selector, multicallData);
        bytes32 opHash = keccak256("op-hash-execute");
        uint256 index = 0;

        bytes memory ret = wallet.runExtension(address(shim), opHash, index, callData);

        assertEq(router.lastSelector(), MockRouter.execute.selector, "selector");
        assertEq(router.lastSender(), address(wallet), "sender");
        assertEq(router.lastValue(), 0, "value should be forwarded");
        assertEq(router.lastData(), multicallData, "calldata");

        MockRouter.Result[] memory decoded = abi.decode(ret, (MockRouter.Result[]));
        assertEq(decoded.length, 1, "result length");
        assertTrue(decoded[0].success, "result success");
        assertEq(decoded[0].returnData, multicallData, "result data");

        bytes32 slot = keccak256(abi.encode(SENTINEL_NAMESPACE, opHash));
        bytes32 stored = vm.load(address(wallet), slot);
        assertEq(stored, SENTINEL_VALUE, "sentinel not set");
    }

    function testPullAndExecuteForwardsValueAndSentinel() public {
        bytes memory multicallData = abi.encode(uint256(456));
        address token = address(0xBEEF);
        uint256 amount = 42;
        bytes memory callData = abi.encodeWithSelector(MockRouter.pullAndExecute.selector, token, amount, multicallData);
        bytes32 opHash = keccak256("op-hash-pull");
        uint256 index = 0;

        vm.deal(address(wallet), 2 ether);

        bytes memory ret = wallet.runExtension{value: 1 ether}(address(shim), opHash, index, callData);

        assertEq(router.lastSelector(), MockRouter.pullAndExecute.selector, "selector");
        assertEq(router.lastSender(), address(wallet), "sender");
        assertEq(router.lastValue(), 1 ether, "value not forwarded");
        assertEq(router.lastToken(), token, "token");
        assertEq(router.lastAmount(), amount, "amount");
        assertEq(router.lastData(), multicallData, "calldata");

        MockRouter.Result[] memory decoded = abi.decode(ret, (MockRouter.Result[]));
        assertEq(decoded.length, 1, "result length");
        assertTrue(decoded[0].success, "result success");

        bytes32 slot = keccak256(abi.encode(SENTINEL_NAMESPACE, opHash));
        bytes32 stored = vm.load(address(wallet), slot);
        assertEq(stored, SENTINEL_VALUE, "sentinel not set");
    }

    function testRouterFailureRevertsAndLeavesSentinelUnset() public {
        router.setNextRevert(bytes("router failed"));

        bytes32 opHash = keccak256("op-hash-fail");
        uint256 index = 0;
        bytes memory callData = abi.encodeWithSelector(MockRouter.execute.selector, bytes("payload"));

        vm.expectRevert(abi.encodeWithSelector(TrailsRouterShim.RouterCallFailed.selector, bytes("router failed")));
        wallet.runExtension(address(shim), opHash, index, callData);

        bytes32 slot = keccak256(abi.encode(SENTINEL_NAMESPACE, opHash));
        bytes32 stored = vm.load(address(wallet), slot);
        assertEq(stored, bytes32(0), "sentinel should remain unset");
    }

    function testDirectCallReverts() public {
        bytes memory callData = abi.encodeWithSelector(MockRouter.execute.selector, bytes("data"));
        vm.expectRevert(TrailsRouterShim.NotDelegateCall.selector);
        shim.handleSequenceDelegateCall(0x0, 0, 0, 0, 0, callData);
    }

    function testPullAndExecuteSelectorConstant() public {
        bytes4 expected = bytes4(keccak256("pullAndExecute(address,uint256,bytes)"));
        bytes4 actual = 0x1bf44db4; // From the test trace
        assertEq(actual, expected, "pullAndExecute selector mismatch");
    }

    function testSimplePullAndExecute() public {
        // Use simpler data like in the execute test
        bytes memory multicallData = abi.encode(uint256(123));
        address token = address(0x123);
        uint256 amount = 1;
        bytes memory callData = abi.encodeWithSelector(MockRouter.pullAndExecute.selector, token, amount, multicallData);
        bytes32 opHash = keccak256("op-hash-simple");
        uint256 index = 0;

        bytes memory ret = wallet.runExtension(address(shim), opHash, index, callData);

        assertEq(router.lastSelector(), MockRouter.pullAndExecute.selector, "selector");
        assertEq(router.lastSender(), address(wallet), "sender");
        assertEq(router.lastValue(), 0, "value");
        assertEq(router.lastToken(), token, "token");
        assertEq(router.lastAmount(), amount, "amount");
        assertEq(router.lastData(), multicallData, "calldata");
    }

    function testInvalidSelectorReverts() public {
        bytes32 opHash = keccak256("op-hash-invalid");
        bytes memory callData = abi.encodeWithSelector(bytes4(keccak256("bad()")));

        vm.expectRevert();
        wallet.runExtension(address(shim), opHash, 0, callData);
    }
}

contract WalletHarness {
    function runExtension(address extension, bytes32 opHash, uint256 index, bytes memory data)
        external
        payable
        returns (bytes memory)
    {
        (bool success, bytes memory ret) = extension.delegatecall(
            abi.encodeWithSelector(
                IDelegatedExtension.handleSequenceDelegateCall.selector, opHash, 0, index, 1, 0, data
            )
        );
        if (!success) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
        return ret;
    }
}

contract MockRouter {
    struct Result {
        bool success;
        bytes returnData;
    }

    bytes4 private _lastSelector;
    address private _lastSender;
    uint256 private _lastValue;
    address private _lastToken;
    uint256 private _lastAmount;
    bytes private _lastData;

    bool private _shouldRevert;
    bytes private _revertData;

    function lastSelector() external view returns (bytes4) {
        return _lastSelector;
    }

    function lastSender() external view returns (address) {
        return _lastSender;
    }

    function lastValue() external view returns (uint256) {
        return _lastValue;
    }

    function lastToken() external view returns (address) {
        return _lastToken;
    }

    function lastAmount() external view returns (uint256) {
        return _lastAmount;
    }

    function lastData() external view returns (bytes memory) {
        return _lastData;
    }

    function setNextRevert(bytes memory revertData) external {
        _shouldRevert = true;
        _revertData = revertData;
    }

    function execute(bytes calldata data) external payable returns (Result[] memory) {
        _record(this.execute.selector, msg.sender, msg.value, address(0), 0, data);
        _maybeRevert();
        return _mockResults(data);
    }

    function pullAndExecute(address token, uint256 amount, bytes calldata data)
        external
        payable
        returns (Result[] memory)
    {
        _record(this.pullAndExecute.selector, msg.sender, msg.value, token, amount, data);
        _maybeRevert();
        return _mockResults(data);
    }

    function _record(bytes4 selector, address sender, uint256 value, address token, uint256 amount, bytes calldata data)
        internal
    {
        _lastSelector = selector;
        _lastSender = sender;
        _lastValue = value;
        _lastToken = token;
        _lastAmount = amount;
        _lastData = data;
    }

    function _maybeRevert() internal {
        if (_shouldRevert) {
            _shouldRevert = false;
            bytes memory revertData = _revertData;
            delete _revertData;
            assembly {
                revert(add(revertData, 32), mload(revertData))
            }
        }
    }

    function _mockResults(bytes calldata data) internal pure returns (Result[] memory results) {
        results = new Result[](1);
        results[0] = Result({success: true, returnData: data});
    }
}
