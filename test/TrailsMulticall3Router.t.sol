// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IMulticall3} from "forge-std/interfaces/IMulticall3.sol";
import {TrailsMulticall3Router} from "src/TrailsMulticall3Router.sol";
import {MockSenderGetter} from "test/mocks/MockSenderGetter.sol";

contract TrailsMulticall3RouterTest is Test {
    TrailsMulticall3Router internal multicallWrapper;
    MockSenderGetter internal getter;

    function setUp() public {
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
        IMulticall3.Result[] memory results = multicallWrapper.aggregate3(calls);

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

        IMulticall3.Result[] memory results = multicallWrapper.aggregate3(calls);
        assertTrue(results[0].success, "call should succeed");
        address returnedSender = abi.decode(results[0].returnData, (address));
        assertEq(returnedSender, address(this), "sender should be the test contract");
    }
} 