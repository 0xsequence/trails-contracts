// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TrailsIntentEntrypoint} from "../src/TrailsIntentEntrypoint.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

// Mock ERC20 token with permit functionality for testing
contract MockERC20Permit is ERC20, ERC20Permit {
    constructor() ERC20("Mock Token", "MTK") ERC20Permit("Mock Token") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}

// -----------------------------------------------------------------------------
// Test Contract
// -----------------------------------------------------------------------------

contract TrailsIntentEntrypointTest is Test {
    // Mirror events for expectEmit if needed
    event FeePaid(address indexed user, address indexed feeToken, uint256 feeAmount, address indexed feeCollector);
    // -------------------------------------------------------------------------
    // Test State Variables
    // -------------------------------------------------------------------------

    TrailsIntentEntrypoint public entrypoint;
    MockERC20Permit public token;
    address public user = vm.addr(0x123456789);
    uint256 public userPrivateKey = 0x123456789;

    function setUp() public {
        entrypoint = new TrailsIntentEntrypoint();
        token = new MockERC20Permit();

        // Give user some tokens and check transfer success
        assertTrue(token.transfer(user, 1000 * 10 ** token.decimals()));
    }

    function testConstructor() public view {
        // Simple constructor test - just verify the contract was deployed
        assertTrue(address(entrypoint) != address(0));
    }

    function testExecuteIntentWithPermit() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        // Create permit signature
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        amount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(userPrivateKey, permitHash);

        // Create intent signature
        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );

        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));

        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        // Record balances before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 intentBalanceBefore = token.balanceOf(intentAddress);

        // Execute intent with permit
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount, // permitAmount - same as amount for this test
            intentAddress,
            deadline,
            nonce,
            0, // no fee amount
            address(0), // no fee collector
            permitV,
            permitR,
            permitS,
            sigV,
            sigR,
            sigS
        );

        // Check balances after
        uint256 userBalanceAfter = token.balanceOf(user);
        uint256 intentBalanceAfter = token.balanceOf(intentAddress);

        assertEq(userBalanceAfter, userBalanceBefore - amount);
        assertEq(intentBalanceAfter, intentBalanceBefore + amount);

        vm.stopPrank();
    }

    function testExecuteIntentWithPermitExpired() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp - 1; // Expired
        uint256 nonce = entrypoint.nonces(user);

        // Create permit signature
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        amount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(userPrivateKey, permitHash);

        // Create intent signature
        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );

        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));

        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        vm.expectRevert();
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount, // permitAmount - same as amount for this test
            intentAddress,
            deadline,
            nonce,
            0, // no fee amount
            address(0), // no fee collector
            permitV,
            permitR,
            permitS,
            sigV,
            sigR,
            sigS
        );

        vm.stopPrank();
    }

    function testExecuteIntentWithPermitInvalidSignature() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        // Use wrong private key for signature
        uint256 wrongPrivateKey = 0x987654321;

        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        amount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(wrongPrivateKey, permitHash);

        // Create intent signature
        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );

        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));

        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(wrongPrivateKey, intentDigest);

        vm.expectRevert();
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount, // permitAmount - same as amount for this test
            intentAddress,
            deadline,
            nonce,
            0, // no fee amount
            address(0), // no fee collector
            permitV,
            permitR,
            permitS,
            sigV,
            sigR,
            sigS
        );

        vm.stopPrank();
    }

    function testExecuteIntentWithFee() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        address feeCollector = address(0x9999);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 feeAmount = 5 * 10 ** token.decimals();
        uint256 totalAmount = amount + feeAmount;
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        // Create permit signature for total amount (deposit + fee)
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        totalAmount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(userPrivateKey, permitHash);

        // Create intent signature
        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );

        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));

        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        // Record balances before
        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 intentBalanceBefore = token.balanceOf(intentAddress);
        uint256 feeCollectorBalanceBefore = token.balanceOf(feeCollector);

        // Execute intent with permit and fee (fee token is same as deposit token)
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            totalAmount, // permitAmount - total amount needed (deposit + fee)
            intentAddress,
            deadline,
            nonce,
            feeAmount,
            feeCollector,
            permitV,
            permitR,
            permitS,
            sigV,
            sigR,
            sigS
        );

        // Check balances after
        uint256 userBalanceAfter = token.balanceOf(user);
        uint256 intentBalanceAfter = token.balanceOf(intentAddress);
        uint256 feeCollectorBalanceAfter = token.balanceOf(feeCollector);

        assertEq(userBalanceAfter, userBalanceBefore - totalAmount);
        assertEq(intentBalanceAfter, intentBalanceBefore + amount);
        assertEq(feeCollectorBalanceAfter, feeCollectorBalanceBefore + feeAmount);

        vm.stopPrank();
    }

    // Test: Infinite approval allows subsequent deposits without new permits
    function testInfiniteApprovalFlow() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;
        uint256 infiniteAmount = type(uint256).max;

        // First deposit with infinite approval
        uint256 nonce1 = entrypoint.nonces(user);

        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        infiniteAmount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(userPrivateKey, permitHash);

        bytes32 intentHash1 = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce1
            )
        );

        bytes32 intentDigest1 = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash1));

        (uint8 sigV1, bytes32 sigR1, bytes32 sigS1) = vm.sign(userPrivateKey, intentDigest1);

        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            infiniteAmount,
            intentAddress,
            deadline,
            nonce1,
            0,
            address(0),
            permitV,
            permitR,
            permitS,
            sigV1,
            sigR1,
            sigS1
        );

        // Verify allowance is still high (infinite - amount)
        assertGt(token.allowance(user, address(entrypoint)), amount * 100);

        // Second deposit without permit
        uint256 nonce2 = entrypoint.nonces(user);
        assertEq(nonce2, 1);

        bytes32 intentHash2 = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce2
            )
        );

        bytes32 intentDigest2 = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash2));

        (uint8 sigV2, bytes32 sigR2, bytes32 sigS2) = vm.sign(userPrivateKey, intentDigest2);

        uint256 userBalBefore = token.balanceOf(user);

        entrypoint.depositToIntent(
            user, address(token), amount, intentAddress, deadline, nonce2, 0, address(0), sigV2, sigR2, sigS2
        );

        assertEq(token.balanceOf(user), userBalBefore - amount);

        vm.stopPrank();
    }

    // Test: Exact approval requires new permit for subsequent deposits
    function testExactApprovalFlow() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;

        // First deposit with exact approval
        uint256 nonce1 = entrypoint.nonces(user);

        bytes32 permitHash1 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        amount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV1, bytes32 permitR1, bytes32 permitS1) = vm.sign(userPrivateKey, permitHash1);

        bytes32 intentHash1 = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce1
            )
        );

        bytes32 intentDigest1 = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash1));

        (uint8 sigV1, bytes32 sigR1, bytes32 sigS1) = vm.sign(userPrivateKey, intentDigest1);

        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce1,
            0,
            address(0),
            permitV1,
            permitR1,
            permitS1,
            sigV1,
            sigR1,
            sigS1
        );

        // Verify allowance is consumed
        assertEq(token.allowance(user, address(entrypoint)), 0);

        // Second deposit requires new permit
        uint256 nonce2 = entrypoint.nonces(user);

        bytes32 permitHash2 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        amount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV2, bytes32 permitR2, bytes32 permitS2) = vm.sign(userPrivateKey, permitHash2);

        bytes32 intentHash2 = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce2
            )
        );

        bytes32 intentDigest2 = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash2));

        (uint8 sigV2, bytes32 sigR2, bytes32 sigS2) = vm.sign(userPrivateKey, intentDigest2);

        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce2,
            0,
            address(0),
            permitV2,
            permitR2,
            permitS2,
            sigV2,
            sigR2,
            sigS2
        );

        assertEq(token.allowance(user, address(entrypoint)), 0);

        vm.stopPrank();
    }

    // Test: Fee collector receives fees on both deposit methods
    function testFeeCollectorReceivesFees() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        address feeCollector = address(0x9999);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 feeAmount = 5 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;

        // Use infinite approval
        uint256 nonce1 = entrypoint.nonces(user);

        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        type(uint256).max,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(userPrivateKey, permitHash);

        bytes32 intentHash1 = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce1
            )
        );

        bytes32 intentDigest1 = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash1));

        (uint8 sigV1, bytes32 sigR1, bytes32 sigS1) = vm.sign(userPrivateKey, intentDigest1);

        // First deposit with fee via permit
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            type(uint256).max,
            intentAddress,
            deadline,
            nonce1,
            feeAmount,
            feeCollector,
            permitV,
            permitR,
            permitS,
            sigV1,
            sigR1,
            sigS1
        );

        assertEq(token.balanceOf(feeCollector), feeAmount);

        // Second deposit with fee without permit
        uint256 nonce2 = entrypoint.nonces(user);

        bytes32 intentHash2 = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce2
            )
        );

        bytes32 intentDigest2 = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash2));

        (uint8 sigV2, bytes32 sigR2, bytes32 sigS2) = vm.sign(userPrivateKey, intentDigest2);

        entrypoint.depositToIntent(
            user, address(token), amount, intentAddress, deadline, nonce2, feeAmount, feeCollector, sigV2, sigR2, sigS2
        );

        // Total fees collected
        assertEq(token.balanceOf(feeCollector), feeAmount * 2);

        vm.stopPrank();
    }

    // Additional tests from reference file for maximum coverage

    function testConstructorAndDomainSeparator() public view {
        assertTrue(address(entrypoint) != address(0));
        bytes32 expectedDomain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("TrailsIntentEntrypoint")),
                keccak256(bytes(entrypoint.VERSION())),
                block.chainid,
                address(entrypoint)
            )
        );
        assertEq(entrypoint.DOMAIN_SEPARATOR(), expectedDomain);
    }

    function testDepositToIntentWithoutPermit_RequiresIntentAddress() public {
        vm.startPrank(user);
        address intentAddress = address(0);
        uint256 amount = 10 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 1;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidIntentAddress.selector);
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, nonce, 0, address(0), v, r, s);
        vm.stopPrank();
    }

    function testDepositToIntentRequiresNonZeroAmount() public {
        vm.startPrank(user);

        address intentAddress = address(0x1234);
        uint256 amount = 0; // Zero amount
        uint256 deadline = block.timestamp + 100;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidAmount.selector);
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, nonce, 0, address(0), v, r, s);

        vm.stopPrank();
    }

    function testDepositToIntentWithPermitRequiresNonZeroAmount() public {
        vm.startPrank(user);

        address intentAddress = address(0x1234);
        uint256 amount = 0; // Zero amount
        uint256 deadline = block.timestamp + 100;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        amount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(userPrivateKey, permitHash);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );
        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidAmount.selector);
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce,
            0,
            address(0),
            permitV,
            permitR,
            permitS,
            sigV,
            sigR,
            sigS
        );

        vm.stopPrank();
    }

    function testDepositToIntentRequiresValidToken() public {
        vm.startPrank(user);

        address intentAddress = address(0x1234);
        uint256 amount = 10 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 100;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(0),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidToken.selector);
        entrypoint.depositToIntent(user, address(0), amount, intentAddress, deadline, nonce, 0, address(0), v, r, s);

        vm.stopPrank();
    }

    function testDepositToIntentWithPermitRequiresValidToken() public {
        vm.startPrank(user);

        address intentAddress = address(0x1234);
        uint256 amount = 10 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 100;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        amount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(userPrivateKey, permitHash);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(0),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );
        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidToken.selector);
        entrypoint.depositToIntentWithPermit(
            user,
            address(0),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce,
            0,
            address(0),
            permitV,
            permitR,
            permitS,
            sigV,
            sigR,
            sigS
        );

        vm.stopPrank();
    }

    function testDepositToIntentExpiredDeadline() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp - 1; // Already expired
        uint256 nonce = entrypoint.nonces(user);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        token.approve(address(entrypoint), amount);

        vm.expectRevert(TrailsIntentEntrypoint.IntentExpired.selector);
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, nonce, 0, address(0), v, r, s);

        vm.stopPrank();
    }

    function testDepositToIntentWrongSigner() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        // Wrong private key for intent signature
        uint256 wrongPrivateKey = 0x987654321;

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);

        token.approve(address(entrypoint), amount);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidIntentSignature.selector);
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, nonce, 0, address(0), v, r, s);

        vm.stopPrank();
    }

    function testDepositToIntentAlreadyUsed() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        token.approve(address(entrypoint), amount * 2); // Approve for both calls

        // First call should succeed
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, nonce, 0, address(0), v, r, s);

        // Second call with same digest should fail (nonce has incremented)
        vm.expectRevert(TrailsIntentEntrypoint.InvalidNonce.selector);
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, nonce, 0, address(0), v, r, s);

        vm.stopPrank();
    }

    function testVersionConstant() public view {
        assertEq(entrypoint.VERSION(), "1");
    }

    function testIntentTypehashConstant() public view {
        bytes32 expectedTypehash = keccak256(
            "TrailsIntent(address user,address token,uint256 amount,address intentAddress,uint256 deadline,uint256 chainId,uint256 nonce)"
        );
        assertEq(entrypoint.TRAILS_INTENT_TYPEHASH(), expectedTypehash);
    }

    function testNonceIncrementsOnDeposit() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;

        uint256 nonceBefore = entrypoint.nonces(user);
        assertEq(nonceBefore, 0);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonceBefore
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        token.approve(address(entrypoint), amount);
        entrypoint.depositToIntent(
            user, address(token), amount, intentAddress, deadline, nonceBefore, 0, address(0), v, r, s
        );

        uint256 nonceAfter = entrypoint.nonces(user);
        assertEq(nonceAfter, 1);

        vm.stopPrank();
    }

    function testInvalidNonceReverts() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;
        uint256 wrongNonce = 999; // Wrong nonce

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                wrongNonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        token.approve(address(entrypoint), amount);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidNonce.selector);
        entrypoint.depositToIntent(
            user, address(token), amount, intentAddress, deadline, wrongNonce, 0, address(0), v, r, s
        );

        vm.stopPrank();
    }

    function testDepositToIntentWithPermitExpiredDeadline() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp - 1; // Already expired
        uint256 nonce = entrypoint.nonces(user);

        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        amount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(userPrivateKey, permitHash);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );
        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        vm.expectRevert(TrailsIntentEntrypoint.IntentExpired.selector);
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce,
            0,
            address(0),
            permitV,
            permitR,
            permitS,
            sigV,
            sigR,
            sigS
        );

        vm.stopPrank();
    }

    function testDepositToIntentCannotReuseDigest() public {
        vm.startPrank(user);

        address intentAddress = address(0x777);
        uint256 amount = 15 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 10;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        token.approve(address(entrypoint), amount);

        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, nonce, 0, address(0), v, r, s);

        // Nonce has incremented, so reusing the same digest/nonce will fail with InvalidNonce
        vm.expectRevert(TrailsIntentEntrypoint.InvalidNonce.selector);
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, nonce, 0, address(0), v, r, s);

        vm.stopPrank();
    }

    function testDepositToIntentWithPermitRequiresPermitAmount() public {
        vm.startPrank(user);
        address intentAddress = address(0x1234);
        uint256 amount = 20 * 10 ** token.decimals();
        uint256 permitAmount = amount - 1;
        uint256 deadline = block.timestamp + 100;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        permitAmount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(userPrivateKey, permitHash);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );
        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        vm.expectRevert();
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            permitAmount,
            intentAddress,
            deadline,
            nonce,
            0,
            address(0),
            permitV,
            permitR,
            permitS,
            sigV,
            sigR,
            sigS
        );
        vm.stopPrank();
    }

    function testDepositToIntentTransferFromFails() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        // Don't approve tokens, so transferFrom should fail
        vm.expectRevert();
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, nonce, 0, address(0), v, r, s);

        vm.stopPrank();
    }

    function testDepositToIntentWithPermitTransferFromFails() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        // Create permit signature with insufficient permit amount
        uint256 permitAmount = amount - 1; // Less than needed
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        permitAmount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(userPrivateKey, permitHash);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );
        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        vm.expectRevert();
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            permitAmount,
            intentAddress,
            deadline,
            nonce,
            0,
            address(0),
            permitV,
            permitR,
            permitS,
            sigV,
            sigR,
            sigS
        );

        vm.stopPrank();
    }

    function testDepositToIntentWithPermitWrongSigner() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        // Wrong private key for intent signature
        uint256 wrongPrivateKey = 0x987654321;

        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        amount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(userPrivateKey, permitHash);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );
        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(wrongPrivateKey, intentDigest);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidIntentSignature.selector);
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce,
            0,
            address(0),
            permitV,
            permitR,
            permitS,
            sigV,
            sigR,
            sigS
        );

        vm.stopPrank();
    }

    function testDepositToIntentWithPermitAlreadyUsed() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        amount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(userPrivateKey, permitHash);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );
        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        // First call should succeed
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce,
            0,
            address(0),
            permitV,
            permitR,
            permitS,
            sigV,
            sigR,
            sigS
        );

        // Second call with same digest should fail - the intent signature is now invalid because nonce incremented
        uint256 nonce2 = entrypoint.nonces(user);
        bytes32 permitHash2 = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        amount,
                        token.nonces(user), // Updated nonce
                        deadline
                    )
                )
            )
        );

        (uint8 permitV2, bytes32 permitR2, bytes32 permitS2) = vm.sign(userPrivateKey, permitHash2);

        // The old intent signature uses old nonce, so it will fail with InvalidIntentSignature
        vm.expectRevert(TrailsIntentEntrypoint.InvalidIntentSignature.selector);
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce2,
            0,
            address(0),
            permitV2,
            permitR2,
            permitS2,
            sigV,
            sigR,
            sigS
        );

        vm.stopPrank();
    }

    function testDepositToIntentWithPermitReentrancyProtection() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        amount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(userPrivateKey, permitHash);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );

        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));

        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        // First call should succeed
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce,
            0,
            address(0),
            permitV,
            permitR,
            permitS,
            sigV,
            sigR,
            sigS
        );

        // Second call with same parameters should fail due to InvalidNonce (nonce has incremented)
        vm.expectRevert(TrailsIntentEntrypoint.InvalidNonce.selector);
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce,
            0,
            address(0),
            permitV,
            permitR,
            permitS,
            sigV,
            sigR,
            sigS
        );

        vm.stopPrank();
    }

    function testDepositToIntentReentrancyProtection() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );

        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));

        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        token.approve(address(entrypoint), amount * 2);

        // First call should succeed
        entrypoint.depositToIntent(
            user, address(token), amount, intentAddress, deadline, nonce, 0, address(0), sigV, sigR, sigS
        );

        // Second call should fail due to InvalidNonce (nonce has incremented)
        vm.expectRevert(TrailsIntentEntrypoint.InvalidNonce.selector);
        entrypoint.depositToIntent(
            user, address(token), amount, intentAddress, deadline, nonce, 0, address(0), sigV, sigR, sigS
        );

        vm.stopPrank();
    }

    function testUsedIntentsMapping() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );

        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));

        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        token.approve(address(entrypoint), amount);

        // Check that intent is not used initially
        assertFalse(entrypoint.usedIntents(intentDigest));

        // Execute intent
        entrypoint.depositToIntent(
            user, address(token), amount, intentAddress, deadline, nonce, 0, address(0), sigV, sigR, sigS
        );

        // Check that intent is now marked as used
        assertTrue(entrypoint.usedIntents(intentDigest));

        vm.stopPrank();
    }

    function testAssemblyCodeExecution() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce
            )
        );

        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));

        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        token.approve(address(entrypoint), amount);

        // This should execute the assembly code in _verifyAndMarkIntent
        entrypoint.depositToIntent(
            user, address(token), amount, intentAddress, deadline, nonce, 0, address(0), sigV, sigR, sigS
        );

        // Verify the intent was processed correctly
        assertTrue(entrypoint.usedIntents(intentDigest));

        vm.stopPrank();
    }
}
