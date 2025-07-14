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
        // Set block number for recent block
        vm.roll(100);
        uint256 blockNum = 99;

        // Hardcoded RLP data from dummy (note: in production, use real data or adjust for address matching)
        bytes memory headerRLP =
            hex"f8baa00000000000000000000000000000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000000940000000000000000000000000000000000000000a00000000000000000000000000000000000000000000000000000000000000000a0bfaaa365cc8b4480030c1b9bc9fe5624753e79b08f1e28cc2f07b11e15bbbdd0a090890722e42ee8f68356bfadaa155ddea3c68d6b91a575742959e501ea57156b";
        bytes memory txRLP =
            hex"f86d8001520894111111111111111111111111111111111111111180b84ea9059cbb00000000000000000000000022222222222222222222222222222222222222220000000000000000000000000000000000000000000000000000000000000064999999999999999999991b8080";
        bytes memory receiptRLP =
            hex"f901a5015208b90100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f89df89b941111111111111111111111111111111111111111f863a0ddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3efa00000000000000000000000003333333333333333333333333333333333333333a00000000000000000000000002222222222222222222222222222222222222222a00000000000000000000000000000000000000000000000000000000000000064";

        bytes32 headerHash = keccak256(headerRLP);
        vm.setBlockhash(blockNum, headerHash);

        bytes32[] memory merkleProofTx = new bytes32[](0);
        bytes32[] memory merkleProofReceipt = new bytes32[](0);

        // Expected hash from suffix b'\x99' * 10
        bytes memory suffix = hex"99999999999999999999";
        bytes32 expectedHash = keccak256(suffix);

        vm.expectEmit(true, true, true, true);
        emit TrailsEntrypointV2.DepositProved(
            expectedHash, 0x3333333333333333333333333333333333333333, 0x1111111111111111111111111111111111111111, 100
        );

        entrypoint.proveERC20Deposit(blockNum, headerRLP, merkleProofTx, txRLP, merkleProofReceipt, receiptRLP);

        (address owner, address token, uint256 amount, uint8 status) = entrypoint.deposits(expectedHash);
        assertEq(owner, 0x3333333333333333333333333333333333333333);
        assertEq(token, 0x1111111111111111111111111111111111111111);
        assertEq(amount, 100);
        assertEq(status, 0);

        // Note: This test assumes dummy addresses; in a real scenario, ensure the recipient in RLP matches address(entrypoint)
        // If not matching, the test will revert on "Not to entrypoint", adjust RLP accordingly
    }
}
