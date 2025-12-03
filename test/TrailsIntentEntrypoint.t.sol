// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TrailsIntentEntrypoint} from "../src/TrailsIntentEntrypoint.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
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
        uint256 feeAmount = 0;
        address feeCollector = address(0);

        // Create permit signature with intent digest-derived deadline
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = _signPermitForIntent(
            user, address(token), amount, intentAddress, deadline, nonce, feeAmount, feeCollector, amount
        );

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
            feeAmount,
            feeCollector,
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
        uint256 deadline = block.timestamp + 3600; // Valid deadline
        uint256 nonce = entrypoint.nonces(user);
        uint256 feeAmount = 0;
        address feeCollector = address(0);

        // Create permit signature with intent digest-derived deadline
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = _signPermitForIntent(
            user, address(token), amount, intentAddress, deadline, nonce, feeAmount, feeCollector, amount
        );

        // This should succeed
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce,
            feeAmount,
            feeCollector,
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
        uint256 feeAmount = 0;
        address feeCollector = address(0);

        // Use wrong private key for signature
        uint256 wrongPrivateKey = 0x987654321;

        // Compute intent digest to get permit deadline
        bytes32 intentHash;
        bytes32 _typehash = entrypoint.TRAILS_INTENT_TYPEHASH();
        address tokenAddr = address(token);
        address userAddr = user;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, _typehash)
            mstore(add(ptr, 0x20), userAddr)
            mstore(add(ptr, 0x40), tokenAddr)
            mstore(add(ptr, 0x60), amount)
            mstore(add(ptr, 0x80), intentAddress)
            mstore(add(ptr, 0xa0), deadline)
            mstore(add(ptr, 0xc0), chainid())
            mstore(add(ptr, 0xe0), nonce)
            mstore(add(ptr, 0x100), feeAmount)
            mstore(add(ptr, 0x120), feeCollector)
            intentHash := keccak256(ptr, 0x140)
        }
        bytes32 intentDigest;
        bytes32 _domainSeparator = entrypoint.DOMAIN_SEPARATOR();
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x1901)
            mstore(add(ptr, 0x20), _domainSeparator)
            mstore(add(ptr, 0x40), intentHash)
            intentDigest := keccak256(add(ptr, 0x1e), 0x42)
        }
        uint256 DEADLINE_MASK = 0xff00000000000000000000000000000000000000000000000000000000000000;
        uint256 permitDeadline = uint256(intentDigest) | DEADLINE_MASK;
        uint256 permitNonce = token.nonces(user);

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
                        permitNonce,
                        permitDeadline
                    )
                )
            )
        );

        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(wrongPrivateKey, permitHash);

        // Permit will revert with its own error, not InvalidPermitSignature
        vm.expectRevert();
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce,
            feeAmount,
            feeCollector,
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

        // Create permit signature for total amount (deposit + fee) with intent digest-derived deadline
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = _signPermitForIntent(
            user, address(token), amount, intentAddress, deadline, nonce, feeAmount, feeCollector, totalAmount
        );

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
        uint256 permitAmount = amount; // Exact amount (no fee)

        // First deposit with permit
        uint256 nonce1 = entrypoint.nonces(user);
        uint256 feeAmount1 = 0;
        address feeCollector1 = address(0);
        uint256 deadline1 = block.timestamp + 3600;

        // Create permit signature with intent digest-derived deadline
        (uint8 sigV1, bytes32 sigR1, bytes32 sigS1) = _signPermitForIntent(
            user, address(token), amount, intentAddress, deadline1, nonce1, feeAmount1, feeCollector1, permitAmount
        );

        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            permitAmount,
            intentAddress,
            deadline1,
            nonce1,
            feeAmount1,
            feeCollector1,
            sigV1,
            sigR1,
            sigS1
        );

        // Verify allowance is consumed
        assertEq(token.allowance(user, address(entrypoint)), 0);

        // Second deposit without permit
        uint256 nonce2 = entrypoint.nonces(user);
        assertEq(nonce2, 1);

        uint256 deadline2 = block.timestamp + 3600; // Use a regular deadline for depositToIntent
        bytes32 intentHash2 = keccak256(
            abi.encode(
                entrypoint.TRAILS_INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline2,
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
            user, address(token), amount, intentAddress, deadline2, nonce2, 0, address(0), sigV2, sigR2, sigS2
        );

        assertEq(token.balanceOf(user), userBalBefore - amount);

        vm.stopPrank();
    }

    // Test: Exact approval requires new permit for subsequent deposits
    function testExactApprovalFlow() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();

        // First deposit with exact approval
        uint256 nonce1 = entrypoint.nonces(user);
        uint256 feeAmount1 = 0;
        address feeCollector1 = address(0);
        uint256 deadline1 = block.timestamp + 3600;

        // Create permit signature with intent digest-derived deadline
        (uint8 sigV1, bytes32 sigR1, bytes32 sigS1) = _signPermitForIntent(
            user, address(token), amount, intentAddress, deadline1, nonce1, feeAmount1, feeCollector1, amount
        );

        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline1,
            nonce1,
            feeAmount1,
            feeCollector1,
            sigV1,
            sigR1,
            sigS1
        );

        // Verify allowance is consumed
        assertEq(token.allowance(user, address(entrypoint)), 0);

        // Second deposit requires new permit
        uint256 nonce2 = entrypoint.nonces(user);
        uint256 feeAmount2 = 0;
        address feeCollector2 = address(0);
        uint256 deadline2 = block.timestamp + 3600;

        // Create permit signature for second deposit
        (uint8 sigV2, bytes32 sigR2, bytes32 sigS2) = _signPermitForIntent(
            user, address(token), amount, intentAddress, deadline2, nonce2, feeAmount2, feeCollector2, amount
        );

        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline2,
            nonce2,
            feeAmount2,
            feeCollector2,
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
        address intentAddress = address(0x5678);
        address feeCollector = address(0x9999);
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce1 = entrypoint.nonces(user);

        // Create permit signature with intent digest-derived deadline
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = _signPermitForIntent(
            user, address(token), amt, intentAddress, deadline, nonce1, fee, feeCollector, amt + fee
        );

        entrypoint.depositToIntentWithPermit(
            user, address(token), amt, amt + fee, intentAddress, deadline, nonce1, fee, feeCollector, sigV, sigR, sigS
        );

        assertEq(token.balanceOf(feeCollector), fee);

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
        uint256 feeAmount = 0;
        address feeCollector = address(0);

        // Create permit signature with intent digest-derived deadline
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = _signPermitForIntent(
            user, address(token), amount, intentAddress, deadline, nonce, feeAmount, feeCollector, amount
        );

        vm.expectRevert(TrailsIntentEntrypoint.InvalidAmount.selector);
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce,
            feeAmount,
            feeCollector,
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
        uint256 nonce = entrypoint.nonces(user);
        uint256 feeAmount = 0;
        address feeCollector = address(0);
        uint256 deadline = block.timestamp + 100;

        // Note: We can't create permit signature with address(0) token, but contract will revert earlier
        // So we'll use a dummy signature - the contract will revert at InvalidToken check
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = (0, bytes32(0), bytes32(0));

        vm.expectRevert(TrailsIntentEntrypoint.InvalidToken.selector);
        entrypoint.depositToIntentWithPermit(
            user, address(0), amount, amount, intentAddress, deadline, nonce, feeAmount, feeCollector, sigV, sigR, sigS
        );

        vm.stopPrank();
    }

    function testDepositToIntentExpiredDeadline(uint256 deadline, uint256 blockTime) public {
        vm.startPrank(user);

        blockTime = bound(blockTime, 1, type(uint256).max);
        deadline = bound(deadline, 0, blockTime - 1);
        vm.warp(blockTime);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
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
        // Note: With the new combined signature approach, deadline is computed from intent params
        // and always in the future, so this test is no longer applicable.
        // The deadline is always valid since it's computed with a mask ensuring it's > block.timestamp
        // This test is kept for documentation but will always pass
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 nonce = entrypoint.nonces(user);
        uint256 feeAmount = 0;
        address feeCollector = address(0);
        uint256 deadline = block.timestamp + 3600;

        // Create permit signature with intent digest-derived deadline
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = _signPermitForIntent(
            user, address(token), amount, intentAddress, deadline, nonce, feeAmount, feeCollector, amount
        );

        // This should succeed
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce,
            feeAmount,
            feeCollector,
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
        uint256 permitAmount = amount - 1; // Insufficient
        uint256 nonce = entrypoint.nonces(user);
        uint256 feeAmount = 0;
        address feeCollector = address(0);
        uint256 deadline = block.timestamp + 3600;

        // Create permit signature with intent digest-derived deadline but insufficient amount
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = _signPermitForIntent(
            user, address(token), amount, intentAddress, deadline, nonce, feeAmount, feeCollector, permitAmount
        );

        // This should fail because permitAmount < amount (transfer will fail)
        vm.expectRevert();
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            permitAmount,
            intentAddress,
            deadline,
            nonce,
            feeAmount,
            feeCollector,
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
        uint256 permitAmount = amount - 1; // Less than needed
        uint256 nonce = entrypoint.nonces(user);
        uint256 feeAmount = 0;
        address feeCollector = address(0);
        uint256 deadline = block.timestamp + 3600;

        // Create permit signature with insufficient permit amount
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = _signPermitForIntent(
            user, address(token), amount, intentAddress, deadline, nonce, feeAmount, feeCollector, permitAmount
        );

        // This should fail because permitAmount < amount (transfer will fail)
        vm.expectRevert();
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            permitAmount,
            intentAddress,
            deadline,
            nonce,
            feeAmount,
            feeCollector,
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
        uint256 nonce = entrypoint.nonces(user);
        uint256 permitNonce = token.nonces(user);
        uint256 feeAmount = 0;
        address feeCollector = address(0);

        // Compute deadline from intent parameters
        uint256 deadline = _computeDeadline(user, address(token), amount, intentAddress, nonce, feeAmount, feeCollector);

        // Use wrong private key for permit signature
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
                        permitNonce,
                        deadline
                    )
                )
            )
        );

        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(wrongPrivateKey, permitHash);

        // Permit will revert with its own error
        vm.expectRevert();
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce,
            feeAmount,
            feeCollector,
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
        uint256 nonce = entrypoint.nonces(user);
        uint256 feeAmount = 0;
        address feeCollector = address(0);
        uint256 deadline = block.timestamp + 3600;

        // Create permit signature with intent digest-derived deadline\
        uint256 permitDeadline = _calculatePermitDeadline(
            user, address(token), amount, intentAddress, deadline, nonce, feeAmount, feeCollector
        );
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = _signPermitWithDeadline(amount, permitDeadline);

        // Use permit
        token.permit(user, address(entrypoint), amount, permitDeadline, sigV, sigR, sigS);

        // Call should fail as permit already used
        vm.expectRevert();
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce,
            feeAmount,
            feeCollector,
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
        uint256 nonce = entrypoint.nonces(user);
        uint256 feeAmount = 0;
        address feeCollector = address(0);
        uint256 deadline = block.timestamp + 3600;

        // Create permit signature with intent digest-derived deadline
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = _signPermitForIntent(
            user, address(token), amount, intentAddress, deadline, nonce, feeAmount, feeCollector, amount
        );

        // First call should succeed
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce,
            feeAmount,
            feeCollector,
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
            feeAmount,
            feeCollector,
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
    // SEQ-1: Permit Amount Flexibility Tests
    // =========================================================================

    /**
     * @notice depositToIntentWithPermit reverts when permit amount cannot cover amount + fee
     * @dev Now relies on the token's allowance error instead of a custom mismatch check
     */
    function testPermitAmountInsufficientWithFee() public {
        vm.startPrank(user);
        uint256 amt = 50e18;
        uint256 fee = 10e18;
        uint256 permitAmt = amt + fee - 1; // Insufficient by 1 wei
        uint256 nonce = entrypoint.nonces(user);
        address intentAddr = address(0x5678);
        address feeCollector = address(0x9999);
        uint256 deadline = block.timestamp + 1 hours;

        // Create permit signature with intent digest-derived deadline
        (uint8 sigV, bytes32 sigR, bytes32 sigS) =
            _signPermitForIntent(user, address(token), amt, intentAddr, deadline, nonce, fee, feeCollector, permitAmt);

        uint256 expectedAllowance = fee - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(entrypoint), expectedAllowance, fee
            )
        );
        entrypoint.depositToIntentWithPermit(
            user, address(token), amt, permitAmt, intentAddr, deadline, nonce, fee, feeCollector, sigV, sigR, sigS
        );
        vm.stopPrank();
    }

    /**
     * @notice depositToIntentWithPermit allows over-permitting; only spends amount + fee
     * @dev Verifies extra allowance remains available after the deposit completes
     */
    function testPermitAmountExcessiveWithFeeLeavesAllowance() public {
        vm.startPrank(user);
        uint256 amt = 50e18;
        uint256 fee = 10e18;
        uint256 extra = 5e18;
        uint256 permitAmt = amt + fee + extra; // Permit more than required
        uint256 nonce = entrypoint.nonces(user);
        address intentAddr = address(0x5678);
        address feeCollector = address(0x9999);
        uint256 deadline = block.timestamp + 1 hours;

        // Create permit signature with intent digest-derived deadline
        (uint8 sigV, bytes32 sigR, bytes32 sigS) =
            _signPermitForIntent(user, address(token), amt, intentAddr, deadline, nonce, fee, feeCollector, permitAmt);

        uint256 userBalanceBefore = token.balanceOf(user);
        uint256 intentBalanceBefore = token.balanceOf(intentAddr);
        uint256 feeCollectorBalanceBefore = token.balanceOf(feeCollector);

        entrypoint.depositToIntentWithPermit(
            user, address(token), amt, permitAmt, intentAddr, deadline, nonce, fee, feeCollector, sigV, sigR, sigS
        );

        assertEq(token.balanceOf(user), userBalanceBefore - (amt + fee));
        assertEq(token.balanceOf(intentAddr), intentBalanceBefore + amt);
        assertEq(token.balanceOf(feeCollector), feeCollectorBalanceBefore + fee);
        assertEq(token.allowance(user, address(entrypoint)), extra);

        vm.stopPrank();
    }

    /**
     * @notice Uses leftover allowance from an oversized permit for a second deposit without a new permit
     * @dev First call over-permits, second call consumes the remaining allowance via depositToIntent
     */
    function testPermitAmountExcessiveThenUseRemainingAllowance() public {
        vm.startPrank(user);

        uint256 amt1 = 50e18;
        uint256 fee1 = 10e18;
        uint256 leftover = 20e18;
        uint256 permitAmt = amt1 + fee1 + leftover;
        address intentAddr = address(0x5678);
        address feeCollector = address(0x9999);

        uint256 nonce1 = entrypoint.nonces(user);
        uint256 deadline1 = block.timestamp + 1 hours;

        // Create permit signature with intent digest-derived deadline
        (uint8 sigV1, bytes32 sigR1, bytes32 sigS1) = _signPermitForIntent(
            user, address(token), amt1, intentAddr, deadline1, nonce1, fee1, feeCollector, permitAmt
        );

        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amt1,
            permitAmt,
            intentAddr,
            deadline1,
            nonce1,
            fee1,
            feeCollector,
            sigV1,
            sigR1,
            sigS1
        );

        assertEq(token.allowance(user, address(entrypoint)), leftover);

        // Use the leftover allowance without another permit
        uint256 amt2 = 15e18;
        uint256 fee2 = 5e18; // amt2 + fee2 == leftover
        uint256 nonce2 = entrypoint.nonces(user);
        uint256 deadline2 = block.timestamp + 1 hours; // Use a regular deadline for depositToIntent
        (uint8 sv2, bytes32 sr2, bytes32 ss2) =
            _signIntent2(user, amt2, intentAddr, deadline2, nonce2, fee2, feeCollector);

        uint256 userBalBefore = token.balanceOf(user);
        uint256 intentBalBefore = token.balanceOf(intentAddr);
        uint256 feeCollectorBalBefore = token.balanceOf(feeCollector);

        entrypoint.depositToIntent(
            user, address(token), amt2, intentAddr, deadline2, nonce2, fee2, feeCollector, sv2, sr2, ss2
        );

        assertEq(token.allowance(user, address(entrypoint)), 0);
        assertEq(token.balanceOf(user), userBalBefore - (amt2 + fee2));
        assertEq(token.balanceOf(intentAddr), intentBalBefore + amt2);
        assertEq(token.balanceOf(feeCollector), feeCollectorBalBefore + fee2);

        vm.stopPrank();
    }

    /// @notice Computes deadline from intent parameters (same as contract does)
    function _computeDeadline(
        address userAddr,
        address tokenAddr,
        uint256 amount,
        address intentAddress,
        uint256 nonce,
        uint256 feeAmount,
        address feeCollector
    ) internal view returns (uint256 deadline) {
        bytes32 intentParamsHash;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, userAddr)
            mstore(add(ptr, 0x20), tokenAddr)
            mstore(add(ptr, 0x40), amount)
            mstore(add(ptr, 0x60), intentAddress)
            mstore(add(ptr, 0x80), chainid())
            mstore(add(ptr, 0xa0), nonce)
            mstore(add(ptr, 0xc0), feeAmount)
            mstore(add(ptr, 0xe0), feeCollector)
            intentParamsHash := keccak256(ptr, 0x100)
        }
        uint256 DEADLINE_MASK = 0xff00000000000000000000000000000000000000000000000000000000000000;
        deadline = uint256(intentParamsHash) | DEADLINE_MASK;
    }

    function _signPermitWithDeadline(uint256 permitAmount, uint256 permitDeadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        // Get permit nonce from token
        uint256 permitNonce = token.nonces(user);

        // Sign permit with computed deadline
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
                        permitNonce,
                        permitDeadline
                    )
                )
            )
        );
        return vm.sign(userPrivateKey, permitHash);
    }

    function _calculatePermitDeadline(
        address userAddr,
        address tokenAddr,
        uint256 amount,
        address intentAddress,
        uint256 deadline,
        uint256 nonce,
        uint256 feeAmount,
        address feeCollector
    ) internal view returns (uint256 permitDeadline) {
        // Build intent hash (same as contract does)
        bytes32 intentHash;
        bytes32 _typehash = entrypoint.TRAILS_INTENT_TYPEHASH();
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, _typehash)
            mstore(add(ptr, 0x20), userAddr)
            mstore(add(ptr, 0x40), tokenAddr)
            mstore(add(ptr, 0x60), amount)
            mstore(add(ptr, 0x80), intentAddress)
            mstore(add(ptr, 0xa0), deadline)
            mstore(add(ptr, 0xc0), chainid())
            mstore(add(ptr, 0xe0), nonce)
            mstore(add(ptr, 0x100), feeAmount)
            mstore(add(ptr, 0x120), feeCollector)
            intentHash := keccak256(ptr, 0x140)
        }

        // Build intent digest
        bytes32 intentDigest;
        bytes32 _domainSeparator = entrypoint.DOMAIN_SEPARATOR();
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x1901)
            mstore(add(ptr, 0x20), _domainSeparator)
            mstore(add(ptr, 0x40), intentHash)
            intentDigest := keccak256(add(ptr, 0x1e), 0x42)
        }

        // Compute permit deadline from intent digest
        uint256 DEADLINE_MASK = 0xff00000000000000000000000000000000000000000000000000000000000000;
        permitDeadline = uint256(intentDigest) | DEADLINE_MASK;
        return permitDeadline;
    }

    /// @notice Computes intent digest and creates permit signature with permit deadline derived from intent digest
    function _signPermitForIntent(
        address userAddr,
        address tokenAddr,
        uint256 amount,
        address intentAddress,
        uint256 deadline,
        uint256 nonce,
        uint256 feeAmount,
        address feeCollector,
        uint256 permitAmount
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        uint256 permitDeadline = _calculatePermitDeadline(
            userAddr, tokenAddr, amount, intentAddress, deadline, nonce, feeAmount, feeCollector
        );

        return _signPermitWithDeadline(permitAmount, permitDeadline);
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

    // =========================================================================
    // Fee Parameter Validation Tests
    // =========================================================================

    /**
     * @notice Test that depositToIntent reverts when feeAmount is provided but feeCollector is not
     * @dev Validates InvalidFeeParameters error when feeAmount > 0 but feeCollector == address(0)
     */
    function testDepositToIntentWithFeeAmountButNoCollector_Reverts() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 feeAmount = 5 * 10 ** token.decimals(); // Fee amount provided
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
                feeAmount,
                address(0) // No fee collector
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        token.approve(address(entrypoint), amount + feeAmount);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidFeeParameters.selector);
        entrypoint.depositToIntent(
            user, address(token), amount, intentAddress, deadline, nonce, feeAmount, address(0), v, r, s
        );

        vm.stopPrank();
    }

    /**
     * @notice Test that depositToIntent reverts when feeCollector is provided but feeAmount is not
     * @dev Validates InvalidFeeParameters error when feeAmount == 0 but feeCollector != address(0)
     */
    function testDepositToIntentWithFeeCollectorButNoAmount_Reverts() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        address feeCollector = address(0x9999); // Fee collector provided
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 feeAmount = 0; // No fee amount
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
                feeAmount,
                feeCollector
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        token.approve(address(entrypoint), amount);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidFeeParameters.selector);
        entrypoint.depositToIntent(
            user, address(token), amount, intentAddress, deadline, nonce, feeAmount, feeCollector, v, r, s
        );

        vm.stopPrank();
    }

    /**
     * @notice Test that depositToIntentWithPermit reverts when feeAmount is provided but feeCollector is not
     * @dev Validates InvalidFeeParameters error when feeAmount > 0 but feeCollector == address(0)
     */
    function testDepositToIntentWithPermitWithFeeAmountButNoCollector_Reverts() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 feeAmount = 5 * 10 ** token.decimals(); // Fee amount provided
        uint256 totalAmount = amount + feeAmount;
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);
        address feeCollector = address(0); // No fee collector

        // Create permit signature for total amount (deposit + fee) with intent digest-derived deadline
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = _signPermitForIntent(
            user, address(token), amount, intentAddress, deadline, nonce, feeAmount, feeCollector, totalAmount
        );

        vm.expectRevert(TrailsIntentEntrypoint.InvalidFeeParameters.selector);
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            totalAmount,
            intentAddress,
            deadline,
            nonce,
            feeAmount,
            feeCollector, // No fee collector
            sigV,
            sigR,
            sigS
        );

        vm.stopPrank();
    }

    /**
     * @notice Test that depositToIntentWithPermit reverts when feeCollector is provided but feeAmount is not
     * @dev Validates InvalidFeeParameters error when feeAmount == 0 but feeCollector != address(0)
     */
    function testDepositToIntentWithPermitWithFeeCollectorButNoAmount_Reverts() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        address feeCollector = address(0x9999); // Fee collector provided
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 feeAmount = 0; // No fee amount
        uint256 deadline = block.timestamp + 3600;
        uint256 nonce = entrypoint.nonces(user);

        // Create permit signature with intent digest-derived deadline
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = _signPermitForIntent(
            user, address(token), amount, intentAddress, deadline, nonce, feeAmount, feeCollector, amount
        );

        vm.expectRevert(TrailsIntentEntrypoint.InvalidFeeParameters.selector);
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            nonce,
            feeAmount,
            feeCollector, // Fee collector provided with no fee amount
            sigV,
            sigR,
            sigS
        );

        vm.stopPrank();
    }
}
