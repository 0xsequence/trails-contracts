// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";
import {TrailsRelayRouter} from "@/TrailsRelayRouter.sol";
import {TrailsRelayConstants} from "@/libraries/TrailsRelayConstants.sol";

contract RevertingReceiver {
    fallback() external payable {
        revert("Always reverts");
    }
}

contract TrailsRelayRouterTest is Test {
    TrailsRelayRouter public router;
    RevertingReceiver public revertingReceiver;

    function setUp() public {
        revertingReceiver = new RevertingReceiver();
        router = new TrailsRelayRouter(address(revertingReceiver));
    }

    function test_execute_valid() public {
        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = Payload.Call({
            to: TrailsRelayConstants.RELAY_MULTICALL_PROXY,
            value: 1 ether,
            data: "",
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: 1 // Revert on error
        });

        bytes memory data = abi.encode(calls);

        vm.expectRevert(TrailsRelayRouter.ExecutionFailed.selector);
        router.execute{value: 1 ether}(data);
    }

    function test_execute_invalidRecipient() public {
        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = Payload.Call({
            to: address(0xdead), // Invalid recipient
            value: 1 ether,
            data: abi.encode(bytes32(uint256(0x123))),
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: 1 // Revert on error
        });

        bytes memory data = abi.encode(calls);

        vm.expectRevert("Invalid relay recipients");
        router.execute{value: 1 ether}(data);
    }

    function test_execute_emptyCalls() public {
        Payload.Call[] memory calls = new Payload.Call[](0);
        bytes memory data = abi.encode(calls);

        vm.expectRevert("Invalid relay recipients");
        router.execute(data);
    }
}
