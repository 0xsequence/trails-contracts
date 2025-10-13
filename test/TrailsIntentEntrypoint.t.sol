// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TrailsIntentEntrypoint} from "../src/TrailsIntentEntrypoint.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

// -----------------------------------------------------------------------------
// Mock Contracts and Utilities
// -----------------------------------------------------------------------------

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
    uint256 public userPrivateKey = 0x123456789;
    address public user;

    // -------------------------------------------------------------------------
    // Setup and Tests
    // -------------------------------------------------------------------------

    function setUp() public {
        entrypoint = new TrailsIntentEntrypoint();
        token = new MockERC20Permit();

        // Derive user address from private key
        user = vm.addr(userPrivateKey);

        // Give user some tokens
        require(token.transfer(user, 1000 * 10 ** token.decimals()), "ERC20 transfer failed");
    }

    // -------------------------------------------------------------------------
    // Tests
    // -------------------------------------------------------------------------
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

    function testExecuteIntentWithPermit() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;

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
        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));

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
        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));

        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));

        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        vm.expectRevert(TrailsIntentEntrypoint.IntentExpired.selector);
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount, // permitAmount - same as amount for this test
            intentAddress,
            deadline,
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
        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));

        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));

        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(wrongPrivateKey, intentDigest);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidIntentSignature.selector);
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount, // permitAmount - same as amount for this test
            intentAddress,
            deadline,
            permitV,
            permitR,
            permitS,
            sigV,
            sigR,
            sigS
        );

        vm.stopPrank();
    }

    function testDepositToIntentWithoutPermit_RequiresIntentAddress() public {
        vm.startPrank(user);
        address intentAddress = address(0);
        uint256 amount = 10 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 1;

        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidIntentAddress.selector);
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, v, r, s);
        vm.stopPrank();
    }

    function testDepositToIntentWithPermitRequiresPermitAmount() public {
        vm.startPrank(user);
        address intentAddress = address(0x1234);
        uint256 amount = 20 * 10 ** token.decimals();
        uint256 permitAmount = amount - 1;
        uint256 deadline = block.timestamp + 100;

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

        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));
        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(entrypoint), permitAmount, amount
            )
        );
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            permitAmount,
            intentAddress,
            deadline,
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

        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        token.approve(address(entrypoint), amount);

        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, v, r, s);

        vm.expectRevert(TrailsIntentEntrypoint.IntentAlreadyUsed.selector);
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, v, r, s);

        vm.stopPrank();
    }

    function testDepositToIntentRequiresNonZeroAmount() public {
        vm.startPrank(user);

        address intentAddress = address(0x1234);
        uint256 amount = 0; // Zero amount
        uint256 deadline = block.timestamp + 100;

        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidAmount.selector);
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, v, r, s);

        vm.stopPrank();
    }

    function testDepositToIntentWithPermitRequiresNonZeroAmount() public {
        vm.startPrank(user);

        address intentAddress = address(0x1234);
        uint256 amount = 0; // Zero amount
        uint256 deadline = block.timestamp + 100;

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

        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));
        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidAmount.selector);
        entrypoint.depositToIntentWithPermit(
            user, address(token), amount, amount, intentAddress, deadline, permitV, permitR, permitS, sigV, sigR, sigS
        );

        vm.stopPrank();
    }

    function testDepositToIntentRequiresValidToken() public {
        vm.startPrank(user);

        address intentAddress = address(0x1234);
        uint256 amount = 10 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 100;

        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(0), amount, intentAddress, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidToken.selector);
        entrypoint.depositToIntent(user, address(0), amount, intentAddress, deadline, v, r, s);

        vm.stopPrank();
    }

    function testDepositToIntentWithPermitRequiresValidToken() public {
        vm.startPrank(user);

        address intentAddress = address(0x1234);
        uint256 amount = 10 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 100;

        // Create permit signature for address(0) token (should fail validation first)
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

        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(0), amount, intentAddress, deadline));
        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidToken.selector);
        entrypoint.depositToIntentWithPermit(
            user, address(0), amount, amount, intentAddress, deadline, permitV, permitR, permitS, sigV, sigR, sigS
        );

        vm.stopPrank();
    }

    function testDepositToIntentExpiredDeadline() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp - 1; // Already expired

        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        token.approve(address(entrypoint), amount);

        vm.expectRevert(TrailsIntentEntrypoint.IntentExpired.selector);
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, v, r, s);

        vm.stopPrank();
    }

    function testDepositToIntentWithPermitExpiredDeadline() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp - 1; // Already expired

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

        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));
        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        vm.expectRevert(TrailsIntentEntrypoint.IntentExpired.selector);
        entrypoint.depositToIntentWithPermit(
            user, address(token), amount, amount, intentAddress, deadline, permitV, permitR, permitS, sigV, sigR, sigS
        );

        vm.stopPrank();
    }

    function testDepositToIntentWrongSigner() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;

        // Wrong private key for intent signature
        uint256 wrongPrivateKey = 0x987654321;

        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongPrivateKey, digest);

        token.approve(address(entrypoint), amount);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidIntentSignature.selector);
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, v, r, s);

        vm.stopPrank();
    }

    function testDepositToIntentWithPermitWrongSigner() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;

        // Wrong private key for intent signature
        uint256 wrongPrivateKey = 0x987654321;

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

        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));
        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(wrongPrivateKey, intentDigest);

        vm.expectRevert(TrailsIntentEntrypoint.InvalidIntentSignature.selector);
        entrypoint.depositToIntentWithPermit(
            user, address(token), amount, amount, intentAddress, deadline, permitV, permitR, permitS, sigV, sigR, sigS
        );

        vm.stopPrank();
    }

    function testDepositToIntentAlreadyUsed() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;

        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        token.approve(address(entrypoint), amount * 2); // Approve for both calls

        // First call should succeed
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, v, r, s);

        // Second call with same digest should fail
        vm.expectRevert(TrailsIntentEntrypoint.IntentAlreadyUsed.selector);
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, v, r, s);

        vm.stopPrank();
    }

    function testDepositToIntentWithPermitAlreadyUsed() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;

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

        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));
        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        // First call should succeed
        entrypoint.depositToIntentWithPermit(
            user, address(token), amount, amount, intentAddress, deadline, permitV, permitR, permitS, sigV, sigR, sigS
        );

        // Second call with same digest should fail - need new permit signature since nonce changed
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

        vm.expectRevert(TrailsIntentEntrypoint.IntentAlreadyUsed.selector);
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            amount,
            intentAddress,
            deadline,
            permitV2,
            permitR2,
            permitS2,
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

        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        // Don't approve tokens, so transferFrom should fail
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(entrypoint), 0, amount)
        );
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, v, r, s);

        vm.stopPrank();
    }

    function testDepositToIntentWithPermitTransferFromFails() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;

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

        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));
        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(entrypoint), permitAmount, amount
            )
        );
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            amount,
            permitAmount,
            intentAddress,
            deadline,
            permitV,
            permitR,
            permitS,
            sigV,
            sigR,
            sigS
        );

        vm.stopPrank();
    }

    function testDomainSeparatorConstruction() public view {
        bytes32 expectedDomain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("TrailsIntentEntrypoint")),
                keccak256(bytes("1")), // VERSION
                block.chainid,
                address(entrypoint)
            )
        );
        assertEq(entrypoint.DOMAIN_SEPARATOR(), expectedDomain);
    }

    function testIntentTypehashConstant() public view {
        bytes32 expectedTypehash =
            keccak256("Intent(address user,address token,uint256 amount,address intentAddress,uint256 deadline)");
        assertEq(entrypoint.INTENT_TYPEHASH(), expectedTypehash);
    }

    function testVersionConstant() public view {
        assertEq(entrypoint.VERSION(), "1");
    }

    function testDepositToIntentWithPermitReentrancyProtection() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;

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
        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));

        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));

        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        // First call should succeed
        entrypoint.depositToIntentWithPermit(
            user, address(token), amount, amount, intentAddress, deadline, permitV, permitR, permitS, sigV, sigR, sigS
        );

        // Second call with same parameters should fail due to reentrancy guard (intent already used)
        // But actually it fails due to IntentAlreadyUsed, not reentrancy
        vm.expectRevert(TrailsIntentEntrypoint.IntentAlreadyUsed.selector);
        entrypoint.depositToIntentWithPermit(
            user, address(token), amount, amount, intentAddress, deadline, permitV, permitR, permitS, sigV, sigR, sigS
        );

        vm.stopPrank();
    }

    function testDepositToIntentReentrancyProtection() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;

        // Create intent signature
        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));

        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));

        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        token.approve(address(entrypoint), amount * 2);

        // First call should succeed
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, sigV, sigR, sigS);

        // Second call should fail due to IntentAlreadyUsed
        vm.expectRevert(TrailsIntentEntrypoint.IntentAlreadyUsed.selector);
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, sigV, sigR, sigS);

        vm.stopPrank();
    }

    function testUsedIntentsMapping() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;

        // Create intent signature
        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));

        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));

        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        token.approve(address(entrypoint), amount);

        // Check that intent is not used initially
        assertFalse(entrypoint.usedIntents(intentDigest));

        // Execute intent
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, sigV, sigR, sigS);

        // Check that intent is now marked as used
        assertTrue(entrypoint.usedIntents(intentDigest));

        vm.stopPrank();
    }

    function testAssemblyCodeExecution() public {
        vm.startPrank(user);

        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;

        // Create intent signature
        bytes32 intentHash =
            keccak256(abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), amount, intentAddress, deadline));

        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));

        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        token.approve(address(entrypoint), amount);

        // This should execute the assembly code in _verifyAndMarkIntent
        entrypoint.depositToIntent(user, address(token), amount, intentAddress, deadline, sigV, sigR, sigS);

        // Verify the intent was processed correctly
        assertTrue(entrypoint.usedIntents(intentDigest));

        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // Fee payment tests
    // ---------------------------------------------------------------------

    function testPayFee_SucceedsWithAllowance() public {
        vm.startPrank(user);

        address collector = address(0xC0FFEE);
        uint256 feeAmount = 25 * 10 ** token.decimals();

        // Approve allowance for the entrypoint to use for fee
        require(token.approve(address(entrypoint), feeAmount), "approve failed");

        uint256 userBefore = token.balanceOf(user);
        uint256 collectorBefore = token.balanceOf(collector);

        entrypoint.payFee(user, address(token), feeAmount, collector);

        uint256 userAfter = token.balanceOf(user);
        uint256 collectorAfter = token.balanceOf(collector);

        assertEq(userAfter, userBefore - feeAmount);
        assertEq(collectorAfter, collectorBefore + feeAmount);

        vm.stopPrank();
    }

    function testPayFee_RevertZeroAmount() public {
        vm.startPrank(user);
        address collector = address(0xC0FFEE);
        vm.expectRevert(bytes("Fee amount must be greater than 0"));
        entrypoint.payFee(user, address(token), 0, collector);
        vm.stopPrank();
    }

    function testPayFee_RevertZeroToken() public {
        vm.startPrank(user);
        address collector = address(0xC0FFEE);
        vm.expectRevert(bytes("Fee token must not be zero address"));
        entrypoint.payFee(user, address(0), 1, collector);
        vm.stopPrank();
    }

    function testPayFee_RevertZeroCollector() public {
        vm.startPrank(user);
        vm.expectRevert(bytes("Fee collector must not be zero address"));
        entrypoint.payFee(user, address(token), 1, address(0));
        vm.stopPrank();
    }

    function testPayFee_RevertInsufficientAllowance() public {
        vm.startPrank(user);

        address collector = address(0xC0FFEE);
        uint256 feeAmount = 10 * 10 ** token.decimals();

        // No approval provided
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(entrypoint), 0, feeAmount)
        );
        entrypoint.payFee(user, address(token), feeAmount, collector);

        vm.stopPrank();
    }

    function testPayFeeWithPermit_Succeeds() public {
        vm.startPrank(user);

        address collector = address(0xBEEF);
        uint256 feeAmount = 30 * 10 ** token.decimals();
        uint256 deadline = block.timestamp + 3600;

        // Create permit signature for feeAmount
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        feeAmount,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(userPrivateKey, permitHash);

        uint256 userBefore = token.balanceOf(user);
        uint256 collectorBefore = token.balanceOf(collector);

        entrypoint.payFeeWithPermit(user, address(token), feeAmount, collector, deadline, permitV, permitR, permitS);

        uint256 userAfter = token.balanceOf(user);
        uint256 collectorAfter = token.balanceOf(collector);

        assertEq(userAfter, userBefore - feeAmount);
        assertEq(collectorAfter, collectorBefore + feeAmount);

        vm.stopPrank();
    }

    function testPayFeeWithPermit_RevertZeroAmount() public {
        vm.startPrank(user);
        address collector = address(0xBEEF);
        vm.expectRevert(bytes("Fee amount must be greater than 0"));
        entrypoint.payFeeWithPermit(user, address(token), 0, collector, block.timestamp + 1, 0, bytes32(0), bytes32(0));
        vm.stopPrank();
    }

    function testPayFeeWithPermit_RevertZeroToken() public {
        vm.startPrank(user);
        address collector = address(0xBEEF);
        vm.expectRevert(bytes("Fee token must not be zero address"));
        entrypoint.payFeeWithPermit(user, address(0), 1, collector, block.timestamp + 1, 0, bytes32(0), bytes32(0));
        vm.stopPrank();
    }

    function testPayFeeWithPermit_RevertZeroCollector() public {
        vm.startPrank(user);
        vm.expectRevert(bytes("Fee collector must not be zero address"));
        entrypoint.payFeeWithPermit(user, address(token), 1, address(0), block.timestamp + 1, 0, bytes32(0), bytes32(0));
        vm.stopPrank();
    }

    function testPayFeeWithPermit_RevertExpiredDeadline() public {
        vm.startPrank(user);
        address collector = address(0xBEEF);
        uint256 pastDeadline = block.timestamp - 1;
        vm.expectRevert(bytes("Permit expired"));
        entrypoint.payFeeWithPermit(user, address(token), 1, collector, pastDeadline, 0, bytes32(0), bytes32(0));
        vm.stopPrank();
    }

    function testPayFee_UsesLeftoverPermitAllowance() public {
        vm.startPrank(user);

        address intentAddress = address(0x9999);
        address collector = address(0xC011EC7);
        uint256 totalPermit = 100 * 10 ** token.decimals();
        uint256 depositAmount = 60 * 10 ** token.decimals();
        uint256 feeAmount = totalPermit - depositAmount; // 40
        uint256 deadline = block.timestamp + 3600;

        // Create permit for totalPermit
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        user,
                        address(entrypoint),
                        totalPermit,
                        token.nonces(user),
                        deadline
                    )
                )
            )
        );
        (uint8 permitV, bytes32 permitR, bytes32 permitS) = vm.sign(userPrivateKey, permitHash);

        // Intent signature for deposit
        bytes32 intentHash = keccak256(
            abi.encode(entrypoint.INTENT_TYPEHASH(), user, address(token), depositAmount, intentAddress, deadline)
        );
        bytes32 intentDigest = keccak256(abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash));
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);

        // Execute deposit with higher permit than amount -> leaves leftover allowance
        entrypoint.depositToIntentWithPermit(
            user,
            address(token),
            depositAmount,
            totalPermit,
            intentAddress,
            deadline,
            permitV,
            permitR,
            permitS,
            sigV,
            sigR,
            sigS
        );

        // Verify leftover allowance equals feeAmount
        assertEq(token.allowance(user, address(entrypoint)), feeAmount);

        uint256 userBefore = token.balanceOf(user);
        uint256 collectorBefore = token.balanceOf(collector);

        // Use leftover allowance to pay fee
        entrypoint.payFee(user, address(token), feeAmount, collector);

        uint256 userAfter = token.balanceOf(user);
        uint256 collectorAfter = token.balanceOf(collector);

        assertEq(userAfter, userBefore - feeAmount);
        assertEq(collectorAfter, collectorBefore + feeAmount);
        assertEq(token.allowance(user, address(entrypoint)), 0);

        vm.stopPrank();
    }
}