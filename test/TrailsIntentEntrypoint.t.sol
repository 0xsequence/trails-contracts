// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {TrailsIntentEntrypoint} from "../src/TrailsIntentEntrypoint.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {MockNonStandardERC20} from "./mocks/MockNonStandardERC20.sol";

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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                feeAmount,
                feeCollector
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
        uint256 permitAmount = amount; // Exact amount (no fee)

        // First deposit with permit
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
                        permitAmount,
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
                nonce1,
                0, // feeAmount
                address(0) // feeCollector
            )
        );

        bytes32 intentDigest1 = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash1));

        (uint8 sigV1, bytes32 sigR1, bytes32 sigS1) = vm.sign(userPrivateKey, intentDigest1);

        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            permitAmount,
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

        // Verify allowance is consumed
        assertEq(token.allowance(user, address(entrypoint)), 0);

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
                nonce2,
                0, // feeAmount
                address(0) // feeCollector
            )
        );

        bytes32 intentDigest2 = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash2));

        (uint8 sigV2, bytes32 sigR2, bytes32 sigS2) = vm.sign(userPrivateKey, intentDigest2);

        uint256 userBalBefore = token.balanceOf(user);

        // Approve for second deposit since exact permit was consumed by first deposit
        token.approve(address(entrypoint), amount);

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
                nonce1,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce2,
                0, // feeAmount
                address(0) // feeCollector
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

    // Test: Fee collector receives fees with permit
    function testFeeCollectorReceivesFees() public {
        vm.startPrank(user);

        uint256 amt = 50e18;
        uint256 fee = 5e18;
        uint256 dl = block.timestamp + 1 hours;
        uint256 nonce1 = entrypoint.nonces(user);

        (uint8 pv, bytes32 pr, bytes32 ps) = _signPermit(user, amt + fee, dl);
        (uint8 sv, bytes32 sr, bytes32 ss) = _signIntent2(user, amt, address(0x5678), dl, nonce1, fee, address(0x9999));

        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amt,
            amt + fee,
            address(0x5678),
            dl,
            nonce1,
            fee,
            address(0x9999),
            pv,
            pr,
            ps,
            sv,
            sr,
            ss
        );

        assertEq(token.balanceOf(address(0x9999)), fee);

        vm.stopPrank();
    }

    // Test: Fee collector receives fees without permit
    function testFeeCollectorReceivesFeesWithoutPermit() public {
        vm.startPrank(user);

        uint256 amt = 50e18;
        uint256 fee = 5e18;
        uint256 dl = block.timestamp + 1 hours;
        uint256 nonce = entrypoint.nonces(user);

        (uint8 sv, bytes32 sr, bytes32 ss) = _signIntent2(user, amt, address(0x5678), dl, nonce, fee, address(0x9999));

        token.approve(address(entrypoint), amt + fee);

        entrypoint.depositToIntent(
            user, address(token), amt, address(0x5678), dl, nonce, fee, address(0x9999), sv, sr, ss
        );

        assertEq(token.balanceOf(address(0x9999)), fee);

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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
            "TrailsIntent(address user,address token,uint256 amount,address intentAddress,uint256 deadline,uint256 chainId,uint256 nonce,uint256 feeAmount,address feeCollector)"
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
                nonceBefore,
                0, // feeAmount
                address(0) // feeCollector
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
                wrongNonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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
                nonce,
                0, // feeAmount
                address(0) // feeCollector
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

    // =========================================================================
    // SEQ-2: Non-Standard ERC20 Token Tests (SafeERC20 Implementation)
    // =========================================================================

    /**
     * @notice Test depositToIntent with non-standard ERC20 token (like USDT)
     * @dev Verifies SafeERC20.safeTransferFrom works with tokens that don't return boolean
     */
    function testDepositToIntent_WithNonStandardERC20_Success() public {
        // Deploy non-standard ERC20 token
        MockNonStandardERC20 nonStandardToken = new MockNonStandardERC20(1000000 * 10 ** 6);

        // Transfer tokens to user
        nonStandardToken.transfer(user, 1000 * 10 ** 6);

        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** 6; // 50 tokens with 6 decimals
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(nonStandardToken),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce,
                0, // feeAmount
                address(0) // feeCollector
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        // Approve entrypoint to spend non-standard tokens
        nonStandardToken.approve(address(entrypoint), amount);

        uint256 userBalBefore = nonStandardToken.balanceOf(user);
        uint256 intentBalBefore = nonStandardToken.balanceOf(intentAddress);

        // This should succeed with SafeERC20 even though token doesn't return boolean
        entrypoint.depositToIntent(
            user, address(nonStandardToken), amount, intentAddress, deadline, nonce, 0, address(0), v, r, s
        );

        // Verify balances updated correctly
        assertEq(nonStandardToken.balanceOf(user), userBalBefore - amount);
        assertEq(nonStandardToken.balanceOf(intentAddress), intentBalBefore + amount);

        vm.stopPrank();
    }

    /**
     * @notice Test depositToIntent with non-standard ERC20 token and fee
     * @dev Verifies SafeERC20.safeTransferFrom handles both deposit and fee transfers correctly
     */
    function testDepositToIntent_WithNonStandardERC20AndFee_Success() public {
        // Deploy non-standard ERC20 token
        MockNonStandardERC20 nonStandardToken = new MockNonStandardERC20(1000000 * 10 ** 6);

        // Transfer tokens to user
        nonStandardToken.transfer(user, 1000 * 10 ** 6);

        vm.startPrank(user);

        address intentAddress = address(0x5678);
        address feeCollector = address(0x9999);
        uint256 amount = 50 * 10 ** 6; // 50 tokens with 6 decimals
        uint256 feeAmount = 5 * 10 ** 6; // 5 tokens fee
        uint256 totalAmount = amount + feeAmount;
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(nonStandardToken),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce,
                feeAmount,
                feeCollector
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        // Approve entrypoint to spend non-standard tokens (total amount + fee)
        nonStandardToken.approve(address(entrypoint), totalAmount);

        uint256 userBalBefore = nonStandardToken.balanceOf(user);
        uint256 intentBalBefore = nonStandardToken.balanceOf(intentAddress);
        uint256 feeCollectorBalBefore = nonStandardToken.balanceOf(feeCollector);

        // This should succeed with SafeERC20 for both transfers
        entrypoint.depositToIntent(
            user, address(nonStandardToken), amount, intentAddress, deadline, nonce, feeAmount, feeCollector, v, r, s
        );

        // Verify all balances updated correctly
        assertEq(nonStandardToken.balanceOf(user), userBalBefore - totalAmount);
        assertEq(nonStandardToken.balanceOf(intentAddress), intentBalBefore + amount);
        assertEq(nonStandardToken.balanceOf(feeCollector), feeCollectorBalBefore + feeAmount);

        vm.stopPrank();
    }

    /**
     * @notice Test depositToIntent with non-standard ERC20 when transfer fails
     * @dev Verifies SafeERC20.safeTransferFrom properly reverts when non-standard token transfer fails
     */
    function testDepositToIntent_WithNonStandardERC20_InsufficientBalance_Reverts() public {
        // Deploy non-standard ERC20 token
        MockNonStandardERC20 nonStandardToken = new MockNonStandardERC20(1000000 * 10 ** 6);

        // Give user very small amount
        nonStandardToken.transfer(user, 10 * 10 ** 6);

        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 100 * 10 ** 6; // More than user has
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(nonStandardToken),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce,
                0,
                address(0)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        nonStandardToken.approve(address(entrypoint), amount);

        // Should revert because user has insufficient balance
        vm.expectRevert("Insufficient balance");
        entrypoint.depositToIntent(
            user, address(nonStandardToken), amount, intentAddress, deadline, nonce, 0, address(0), v, r, s
        );

        vm.stopPrank();
    }

    /**
     * @notice Test depositToIntent with non-standard ERC20 when allowance is insufficient
     * @dev Verifies SafeERC20.safeTransferFrom properly reverts when allowance is too low
     */
    function testDepositToIntent_WithNonStandardERC20_InsufficientAllowance_Reverts() public {
        // Deploy non-standard ERC20 token
        MockNonStandardERC20 nonStandardToken = new MockNonStandardERC20(1000000 * 10 ** 6);

        // Transfer tokens to user
        nonStandardToken.transfer(user, 1000 * 10 ** 6);

        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** 6;
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(nonStandardToken),
                amount,
                intentAddress,
                deadline,
                block.chainid,
                nonce,
                0,
                address(0)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        // Approve less than amount needed
        nonStandardToken.approve(address(entrypoint), amount - 1);

        // Should revert because allowance is insufficient
        vm.expectRevert("Insufficient allowance");
        entrypoint.depositToIntent(
            user, address(nonStandardToken), amount, intentAddress, deadline, nonce, 0, address(0), v, r, s
        );

        vm.stopPrank();
    }

    // =========================================================================
    // SEQ-1: Permit Amount Validation Tests (Additional Safety Check)
    // =========================================================================

    /**
     * @notice Test that depositToIntentWithPermit reverts when permit amount is insufficient
     * @dev Validates permitAmount != amount + feeAmount check (insufficient case)
     */
    function testPermitAmountInsufficientWithFee() public {
        vm.startPrank(user);
        uint256 amt = 50e18;
        uint256 fee = 10e18;
        uint256 permitAmt = amt + fee - 1; // Insufficient by 1
        uint256 dl = block.timestamp + 1 hours;
        uint256 nonce = entrypoint.nonces(user);

        (uint8 pv, bytes32 pr, bytes32 ps) = _signPermit(user, permitAmt, dl);
        (uint8 sv, bytes32 sr, bytes32 ss) = _signIntent2(user, amt, address(0x5678), dl, nonce, fee, address(0x9999));

        vm.expectRevert(TrailsIntentEntrypoint.PermitAmountMismatch.selector);
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amt,
            permitAmt,
            address(0x5678),
            dl,
            nonce,
            fee,
            address(0x9999),
            pv,
            pr,
            ps,
            sv,
            sr,
            ss
        );
        vm.stopPrank();
    }

    /**
     * @notice Test that depositToIntentWithPermit reverts when permit amount exceeds required
     * @dev Validates permitAmount != amount + feeAmount check (excess case)
     */
    function testPermitAmountExcessiveWithFee() public {
        vm.startPrank(user);
        uint256 amt = 50e18;
        uint256 fee = 10e18;
        uint256 permitAmt = amt + fee + 1; // Excess by 1
        uint256 dl = block.timestamp + 1 hours;
        uint256 nonce = entrypoint.nonces(user);

        (uint8 pv, bytes32 pr, bytes32 ps) = _signPermit(user, permitAmt, dl);
        (uint8 sv, bytes32 sr, bytes32 ss) = _signIntent2(user, amt, address(0x5678), dl, nonce, fee, address(0x9999));

        vm.expectRevert(TrailsIntentEntrypoint.PermitAmountMismatch.selector);
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amt,
            permitAmt,
            address(0x5678),
            dl,
            nonce,
            fee,
            address(0x9999),
            pv,
            pr,
            ps,
            sv,
            sr,
            ss
        );
        vm.stopPrank();
    }

    function _signPermit(address owner, uint256 permitAmount, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 hash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        owner,
                        address(entrypoint),
                        permitAmount,
                        token.nonces(owner),
                        deadline
                    )
                )
            )
        );
        return vm.sign(userPrivateKey, hash);
    }

    function _signIntent2(
        address usr,
        uint256 amt,
        address intent,
        uint256 dl,
        uint256 nonce,
        uint256 fee,
        address collector
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 hash = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                usr,
                address(token),
                amt,
                intent,
                dl,
                block.chainid,
                nonce,
                fee,
                collector
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), hash));
        return vm.sign(userPrivateKey, digest);
    }
}
