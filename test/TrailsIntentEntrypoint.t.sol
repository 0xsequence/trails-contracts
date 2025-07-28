// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TrailsIntentEntrypoint.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

// Mock ERC20 token with permit functionality for testing
contract MockERC20Permit is ERC20, ERC20Permit {
    constructor() ERC20("Mock Token", "MTK") ERC20Permit("Mock Token") {
        _mint(msg.sender, 1000000 * 10**decimals());
    }
}

contract TrailsIntentEntrypointTest is Test {
    TrailsIntentEntrypoint public entrypoint;
    MockERC20Permit public token;
    address public user;
    uint256 public userPrivateKey = 0x123456789;

    function setUp() public {
        user = vm.addr(userPrivateKey); // derive address from private key
        entrypoint = new TrailsIntentEntrypoint();
        token = new MockERC20Permit();
        
        // Give user some tokens
        token.transfer(user, 1000 * 10**token.decimals());
    }

    function testConstructor() public view {
        // Simple constructor test - just verify the contract was deployed
        assertTrue(address(entrypoint) != address(0));
    }

    function testExecuteIntentWithPermit() public {
        vm.startPrank(user);
        
        address intentAddress = address(0x5678);
        uint256 amount = 50 * 10**token.decimals();
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
        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline
            )
        );
        
        bytes32 intentDigest = keccak256(
            abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash)
        );
        
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
        uint256 amount = 50 * 10**token.decimals();
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
        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline
            )
        );
        
        bytes32 intentDigest = keccak256(
            abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash)
        );
        
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(userPrivateKey, intentDigest);
        
        vm.expectRevert();
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
        uint256 amount = 50 * 10**token.decimals();
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
        bytes32 intentHash = keccak256(
            abi.encode(
                entrypoint.INTENT_TYPEHASH(),
                user,
                address(token),
                amount,
                intentAddress,
                deadline
            )
        );
        
        bytes32 intentDigest = keccak256(
            abi.encodePacked("\x19\x01", entrypoint.DOMAIN_SEPARATOR(), intentHash)
        );
        
        (uint8 sigV, bytes32 sigR, bytes32 sigS) = vm.sign(wrongPrivateKey, intentDigest);
        
        vm.expectRevert();
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
} 