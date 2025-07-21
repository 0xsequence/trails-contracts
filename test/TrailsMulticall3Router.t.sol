// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";
import {TrailsMulticall3Router} from "src/TrailsMulticall3Router.sol";
import {MockSenderGetter} from "test/mocks/MockSenderGetter.sol";

// Mock Multicall3 contract for testing that preserves msg.sender via delegatecall
contract MockMulticall3 {
    function aggregate3(IMulticall3.Call3[] calldata calls)
        external
        payable
        returns (IMulticall3.Result[] memory results)
    {
        results = new IMulticall3.Result[](calls.length);
        for (uint256 i = 0; i < calls.length; i++) {
            // Use delegatecall to preserve msg.sender from the TrailsMulticall3Router context
            (bool success, bytes memory returnData) = calls[i].target.delegatecall(calls[i].callData);
            results[i] = IMulticall3.Result({success: success || calls[i].allowFailure, returnData: returnData});
        }
    }
}

contract TrailsMulticall3RouterTest is Test {
    TrailsMulticall3Router internal multicallWrapper;
    MockSenderGetter internal getter;
    MockMulticall3 internal mockMulticall3;

    function setUp() public {
        // Deploy mock multicall3 at the expected address
        mockMulticall3 = new MockMulticall3();
        vm.etch(0xcA11bde05977b3631167028862bE2a173976CA11, address(mockMulticall3).code);

        multicallWrapper = new TrailsMulticall3Router();
        getter = new MockSenderGetter();
    }

    function test_WhenCalledFromEOA_ShouldPreserveEOAAsSender() public {
        address eoa = makeAddr("eoa");

        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](1);
        calls[0] = IMulticall3.Call3({
            target: address(getter),
            allowFailure: false,
            callData: abi.encodeWithSignature("getSender()")
        });

        vm.prank(eoa, eoa);
        bytes memory callData = abi.encodeWithSelector(IMulticall3.aggregate3.selector, calls);
        IMulticall3.Result[] memory results = multicallWrapper.execute(callData);

        assertTrue(results[0].success, "call should succeed");
        address returnedSender = abi.decode(results[0].returnData, (address));
        assertEq(returnedSender, eoa, "sender should be the EOA");
    }

    function test_WhenCalledFromContract_ShouldPreserveContractAsSender() public {
        IMulticall3.Call3[] memory calls = new IMulticall3.Call3[](1);
        calls[0] = IMulticall3.Call3({
            target: address(getter),
            allowFailure: false,
            callData: abi.encodeWithSignature("getSender()")
        });

        bytes memory callData = abi.encodeWithSelector(IMulticall3.aggregate3.selector, calls);
        IMulticall3.Result[] memory results = multicallWrapper.execute(callData);
        assertTrue(results[0].success, "call should succeed");
        address returnedSender = abi.decode(results[0].returnData, (address));
        assertEq(returnedSender, address(this), "sender should be the test contract");
    }
}
