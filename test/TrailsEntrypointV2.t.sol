// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "@/TrailsEntrypointV2.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TrailsEntrypointV2Test is Test {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    TrailsEntrypointV2 public entrypoint;
    MockERC20 public token;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public relayer = address(0x4);

    uint256 public user1PrivateKey = 0x12345;
    uint256 public user2PrivateKey = 0x67890;

    TrailsEntrypointV2.Intent public testIntent;
    bytes32 public testTransferId;
    bytes32 public testIntentHash;

    event TransferReceived(
        bytes32 indexed transferId, address indexed sender, address token, uint256 amount, bytes intentData
    );
    event IntentCommitted(
        bytes32 indexed intentHash, bytes32 indexed transferId, address indexed sender, TrailsEntrypointV2.Intent intent
    );
    event IntentProven(bytes32 indexed intentHash, address indexed prover, bytes signature);
    event IntentExecuted(bytes32 indexed intentHash, bool success, bytes returnData);
    event IntentExpired(bytes32 indexed intentHash, address indexed sender);
    event TransferExpired(bytes32 indexed transferId, address indexed sender);
    event EmergencyWithdraw(bytes32 indexed intentHash, address indexed owner, uint256 amount);

    function setUp() public {
        vm.prank(owner);
        entrypoint = new TrailsEntrypointV2();
        token = new MockERC20();

        // Setup test intent with calls to burn ETH to zero address
        TrailsEntrypointV2.Call[] memory testCalls = new TrailsEntrypointV2.Call[](1);
        testCalls[0] = TrailsEntrypointV2.Call({
            target: address(0), // Burn to zero address
            data: "",
            value: 1 ether
        });

        testIntent = TrailsEntrypointV2.Intent({
            sender: user1,
            token: address(0), // ETH
            amount: 1 ether,
            calls: testCalls, // User commits to these exact calls
            nonce: 0,
            deadline: block.timestamp + 3600
        });

        // Fund users
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        token.mint(user1, 1000 * 10 ** 18);
        token.mint(user2, 1000 * 10 ** 18);

        vm.prank(user1);
        token.approve(address(entrypoint), type(uint256).max);
    }

    // Test the new flow: User transfers first, then relayer commits
    function testETHTransferFlow() public {
        // Step 1: User makes 1-click ETH transfer with intent data (ONLY USER ACTION)
        bytes memory intentData = abi.encode(testIntent);

        vm.prank(user1);
        (bool success,) = address(entrypoint).call{value: 1 ether}(intentData);
        assertTrue(success);

        // Get the actual transfer ID from events
        // In practice, relayer would monitor TransferReceived events
        // For testing, we'll compute it the same way the contract does
        testTransferId = keccak256(abi.encodePacked(block.timestamp, user1, uint256(1 ether), intentData, tx.gasprice));

        // Verify transfer was recorded
        TrailsEntrypointV2.PendingTransfer memory transfer = entrypoint.getPendingTransfer(testTransferId);
        assertEq(transfer.sender, user1);
        assertEq(transfer.token, address(0));
        assertEq(transfer.amount, 1 ether);
        assertFalse(transfer.committed);

        // Verify contract has the ETH before execution
        uint256 contractBalanceBefore = address(entrypoint).balance;
        assertEq(contractBalanceBefore, 1 ether);

        // Step 2: Single call does everything: commit + prove + execute
        // Calls are embedded in the intent, so user committed to exact execution
        vm.prank(relayer);
        testIntentHash = entrypoint.commitProveAndExecuteIntent(testTransferId, testIntent);

        // Verify transfer is now committed
        transfer = entrypoint.getPendingTransfer(testTransferId);
        assertTrue(transfer.committed);

        // Verify everything completed successfully in one call
        uint256 contractBalanceAfter = address(entrypoint).balance;
        assertEq(contractBalanceAfter, 0); // Contract should have no ETH left
        assertEq(address(0).balance, 1 ether); // Zero address should have the ETH (burned)

        // Verify intent is marked as executed
        TrailsEntrypointV2.DepositState memory finalDeposit = entrypoint.getDeposit(testIntentHash);
        assertEq(finalDeposit.owner, user1);
        assertEq(finalDeposit.token, address(0));
        assertEq(finalDeposit.amount, 1 ether);
        assertEq(finalDeposit.status, uint8(TrailsEntrypointV2.IntentStatus.Executed));
        assertEq(entrypoint.nonces(user1), 1);
    }

    function testERC20TransferFlow() public {
        // Setup ERC20 intent with empty calls (just holding tokens)
        TrailsEntrypointV2.Call[] memory emptyCalls = new TrailsEntrypointV2.Call[](0);

        TrailsEntrypointV2.Intent memory erc20Intent = TrailsEntrypointV2.Intent({
            sender: user1,
            token: address(token),
            amount: 100 * 10 ** 18,
            calls: emptyCalls, // No calls, just holding the tokens
            nonce: 0,
            deadline: block.timestamp + 3600
        });

        // Step 1: User makes 1-click ERC20 transfer
        bytes memory intentData = abi.encode(erc20Intent);

        vm.prank(user1);
        entrypoint.depositERC20WithIntent(address(token), 100 * 10 ** 18, intentData);

        assertEq(token.balanceOf(address(entrypoint)), 100 * 10 ** 18);

        // Step 2: Relayer commits intent
        testTransferId = keccak256(
            abi.encodePacked(block.timestamp, user1, address(token), uint256(100 * 10 ** 18), intentData, tx.gasprice)
        );

        vm.prank(relayer);
        bytes32 intentHash = entrypoint.commitIntent(testTransferId, erc20Intent);

        TrailsEntrypointV2.DepositState memory deposit = entrypoint.getDeposit(intentHash);
        assertEq(deposit.token, address(token));
        assertEq(deposit.amount, 100 * 10 ** 18);
    }

    function testTransferWithoutCommitment() public {
        // User makes transfer
        bytes memory intentData = abi.encode(testIntent);

        vm.prank(user1);
        (bool success,) = address(entrypoint).call{value: 1 ether}(intentData);
        assertTrue(success);

        testTransferId = keccak256(abi.encodePacked(block.timestamp, user1, uint256(1 ether), intentData, tx.gasprice));

        // Verify transfer is pending
        TrailsEntrypointV2.PendingTransfer memory transfer = entrypoint.getPendingTransfer(testTransferId);
        assertEq(transfer.sender, user1);
        assertFalse(transfer.committed);

        // User can expire and reclaim after deadline
        vm.warp(block.timestamp + 86401); // Past MAX_INTENT_DEADLINE

        uint256 balanceBefore = user1.balance;
        vm.prank(user1);
        entrypoint.expireTransfer(testTransferId);

        assertEq(user1.balance, balanceBefore + 1 ether);
    }

    function testRelayerCommitValidation() public {
        // User makes transfer
        bytes memory intentData = abi.encode(testIntent);

        vm.prank(user1);
        address(entrypoint).call{value: 1 ether}(intentData);

        testTransferId = keccak256(abi.encodePacked(block.timestamp, user1, uint256(1 ether), intentData, tx.gasprice));

        // Test invalid intent (wrong amount)
        TrailsEntrypointV2.Intent memory wrongIntent = testIntent;
        wrongIntent.amount = 2 ether;

        vm.prank(relayer);
        vm.expectRevert(TrailsEntrypointV2.InvalidAmount.selector);
        entrypoint.commitIntent(testTransferId, wrongIntent);

        // Test invalid intent (wrong sender)
        wrongIntent = testIntent;
        wrongIntent.sender = user2;

        vm.prank(relayer);
        vm.expectRevert(TrailsEntrypointV2.InvalidSender.selector);
        entrypoint.commitIntent(testTransferId, wrongIntent);

        // Test invalid intent (wrong token)
        wrongIntent = testIntent;
        wrongIntent.token = address(token);

        vm.prank(relayer);
        vm.expectRevert(TrailsEntrypointV2.InvalidToken.selector);
        entrypoint.commitIntent(testTransferId, wrongIntent);
    }

    function testDuplicateCommit() public {
        // User makes transfer
        bytes memory intentData = abi.encode(testIntent);

        vm.prank(user1);
        address(entrypoint).call{value: 1 ether}(intentData);

        testTransferId = keccak256(abi.encodePacked(block.timestamp, user1, uint256(1 ether), intentData, tx.gasprice));

        // First commit should succeed
        vm.prank(relayer);
        entrypoint.commitIntent(testTransferId, testIntent);

        // Second commit should fail
        vm.prank(relayer);
        vm.expectRevert(TrailsEntrypointV2.TransferAlreadyCommitted.selector);
        entrypoint.commitIntent(testTransferId, testIntent);
    }

    function testReceiveFunction() public {
        vm.expectRevert("ETH transfers must include intent data in calldata - use fallback function");
        (bool success,) = address(entrypoint).call{value: 1 ether}("");
        // The call should revert, so we don't need to check success
    }

    function testInvalidTransferId() public {
        vm.prank(relayer);
        vm.expectRevert(TrailsEntrypointV2.TransferNotFound.selector);
        entrypoint.commitIntent(bytes32(uint256(0x123)), testIntent);
    }

    function testIntentHashConsistency() public {
        bytes32 hash1 = entrypoint.hashIntent(testIntent);
        bytes32 hash2 = entrypoint.hashIntent(testIntent);

        assertEq(hash1, hash2);

        // Different nonce should produce different hash
        testIntent.nonce = 1;
        bytes32 hash3 = entrypoint.hashIntent(testIntent);
        assertTrue(hash1 != hash3);
    }

    function testInvalidIntentValidation() public {
        // Test with zero sender
        TrailsEntrypointV2.Intent memory invalidIntent = testIntent;
        invalidIntent.sender = address(0);

        vm.expectRevert(TrailsEntrypointV2.InvalidSender.selector);
        entrypoint.hashIntent(invalidIntent);

        // Test with zero amount
        invalidIntent = testIntent;
        invalidIntent.amount = 0;

        vm.expectRevert(TrailsEntrypointV2.InvalidAmount.selector);
        entrypoint.hashIntent(invalidIntent);

        // Test with expired deadline
        invalidIntent = testIntent;
        invalidIntent.deadline = block.timestamp - 1;

        vm.expectRevert(TrailsEntrypointV2.IntentHasExpired.selector);
        entrypoint.hashIntent(invalidIntent);
    }

    function testOwnershipTransfer() public {
        vm.prank(owner);
        entrypoint.transferOwnership(user1);

        // Old owner should not be able to pause
        vm.prank(owner);
        vm.expectRevert(TrailsEntrypointV2.Unauthorized.selector);
        entrypoint.setPaused(true);

        // New owner should be able to pause
        vm.prank(user1);
        entrypoint.setPaused(true);
    }

    function testPauseUnpause() public {
        vm.prank(owner);
        entrypoint.setPaused(true);

        // Transfer should fail when paused
        bytes memory intentData = abi.encode(testIntent);
        vm.prank(user1);
        vm.expectRevert(TrailsEntrypointV2.ContractPaused.selector);
        address(entrypoint).call{value: 1 ether}(intentData);

        vm.prank(owner);
        entrypoint.setPaused(false);

        // Transfer should succeed after unpause
        vm.prank(user1);
        (bool success,) = address(entrypoint).call{value: 1 ether}(intentData);
        assertTrue(success);
    }

    function testUltimateRelayerExperience() public {
        // This test shows the absolute minimal relayer flow

        // First create the complex intent with the specific calls
        TrailsEntrypointV2.Call[] memory complexCalls = new TrailsEntrypointV2.Call[](2);

        // Call 1: Send 0.5 ETH to user2
        complexCalls[0] = TrailsEntrypointV2.Call({target: user2, data: "", value: 0.5 ether});

        // Call 2: Send remaining 0.5 ETH to zero address (burn)
        complexCalls[1] = TrailsEntrypointV2.Call({target: address(0), data: "", value: 0.5 ether});

        TrailsEntrypointV2.Intent memory complexIntent = TrailsEntrypointV2.Intent({
            sender: user1,
            token: address(0),
            amount: 1 ether,
            calls: complexCalls, // User commits to these exact calls
            nonce: 0,
            deadline: block.timestamp + 3600
        });

        // Step 1: User makes 1-click transfer with complex intent
        bytes memory complexIntentData = abi.encode(complexIntent);
        vm.prank(user1);
        (bool success,) = address(entrypoint).call{value: 1 ether}(complexIntentData);
        assertTrue(success);

        // Get transfer ID
        bytes32 transferId =
            keccak256(abi.encodePacked(block.timestamp, user1, uint256(1 ether), complexIntentData, tx.gasprice));

        uint256 user2BalanceBefore = user2.balance;
        uint256 contractBalanceBefore = address(entrypoint).balance;

        // Single relayer call handles everything!
        vm.prank(relayer);
        bytes32 intentHash = entrypoint.commitProveAndExecuteIntent(transferId, complexIntent);

        // Verify complex execution worked
        assertEq(user2.balance, user2BalanceBefore + 0.5 ether); // user2 got 0.5 ETH
        assertEq(address(0).balance, 0.5 ether); // 0.5 ETH burned
        assertEq(address(entrypoint).balance, 0); // Contract has no ETH left

        // Verify intent is executed
        TrailsEntrypointV2.DepositState memory deposit = entrypoint.getDeposit(intentHash);
        assertEq(deposit.status, uint8(TrailsEntrypointV2.IntentStatus.Executed));

        // Ultimate UX achieved:
        // - User: 1 transaction
        // - Relayer: 1 transaction
        // - Result: Complex multi-call execution complete
    }
}
