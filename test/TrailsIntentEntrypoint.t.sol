// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TrailsIntentEntrypoint.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
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
        token.transfer(user, 1000 * 10 ** token.decimals());
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
}
