// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TrailsCCTPV2Router} from "@/TrailsCCTPV2Router.sol";
import {MockTrailsCCTPV2Router} from "./mocks/MockTrailsCCTPV2Router.sol";
import {MockRevertingContract} from "./mocks/MockRevertingContract.sol";
import {ITokenMessengerV2} from "@/interfaces/TrailsCCTPV2.sol";
import {Vm} from "forge-std/Vm.sol";

contract TrailsCCTPV2RouterTest is Test {
    TrailsCCTPV2Router router;

    function setUp() public {
        router = new TrailsCCTPV2Router();
    }

    function test_execute_success() public {
        bytes memory data = abi.encodeWithSelector(
            ITokenMessengerV2.depositForBurnWithHook.selector,
            1 ether,
            0,
            bytes32(0),
            bytes32(0),
            bytes32(0),
            bytes32(0)
        );
        // In the test environment, delegatecall to an address with no code returns success.
        // This test verifies that the call doesn't revert when the selector is valid.
        router.execute(data);
    }

    function test_execute_revert_with_invalid_calldata() public {
        bytes memory data = abi.encodeWithSelector(bytes4(0xdeadbeef));
        vm.expectRevert("Invalid CCTP calldata");
        router.execute(data);
    }

    function test_execute_revert_on_failed_delegatecall() public {
        MockRevertingContract revertingContract = new MockRevertingContract();
        MockTrailsCCTPV2Router mockRouter = new MockTrailsCCTPV2Router(address(revertingContract));

        bytes memory data = abi.encodeWithSelector(ITokenMessengerV2.depositForBurnWithHook.selector);
        vm.expectRevert(bytes("ExecutionFailed()"));
        mockRouter.execute(data);
    }
}
