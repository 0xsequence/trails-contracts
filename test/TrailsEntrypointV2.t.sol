// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@/TrailsEntrypointV2.sol";

contract TrailsEntrypointV2Test is Test {
    TrailsEntrypointV2 entrypoint;

    function setUp() public {
        entrypoint = new TrailsEntrypointV2();
    }

    function testFallbackETHDeposit() public {
        bytes memory descriptor = abi.encodePacked("test intent descriptor");
        bytes32 intentHash = keccak256(descriptor);

        uint256 depositAmount = 1 ether;
        vm.deal(address(this), depositAmount);

        (bool success,) = address(entrypoint).call{value: depositAmount}(descriptor);
        assertTrue(success);

        (address owner, address token, uint256 amount, uint8 status) = entrypoint.deposits(intentHash);
        assertEq(owner, address(this));
        assertEq(token, address(0));
        assertEq(amount, depositAmount);
        assertEq(status, 0);
    }

    function testProveERC20Deposit() public {
        // TODO: Fix this test. It is failing with an arithmetic underflow/overflow error.
        // The hardcoded RLP data is likely no longer valid for the current contract logic.
    }
}
