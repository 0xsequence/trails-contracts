// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title TrailsIntentEntrypoint
/// @author Miguel Mota
/// @notice A contract to facilitate deposits to intent addresses with off-chain signed intents.
contract TrailsIntentEntrypoint is ReentrancyGuard {
    using ECDSA for bytes32;

    bytes32 public constant INTENT_TYPEHASH =
        keccak256("Intent(address user,address token,uint256 amount,address intentAddress,uint256 deadline)");
    string public constant VERSION = "1";

    bytes32 public immutable DOMAIN_SEPARATOR;

    mapping(bytes32 => bool) public usedIntents;

    event IntentDeposit(address indexed user, address indexed intentAddress, uint256 amount);

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("TrailsIntentEntrypoint")),
                keccak256(bytes(VERSION)),
                block.chainid,
                address(this)
            )
        );
    }

    function depositToIntentWithPermit(
        address user,
        address token,
        uint256 amount,
        uint256 permitAmount,
        address intentAddress,
        uint256 deadline,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) external nonReentrant {
        _verifyAndMarkIntent(user, token, amount, intentAddress, deadline, sigV, sigR, sigS);

        // Permit this contract to spend user's tokens
        IERC20Permit(token).permit(user, address(this), permitAmount, deadline, permitV, permitR, permitS);

        // Transfer tokens to intent address
        IERC20(token).transferFrom(user, intentAddress, amount);

        emit IntentDeposit(user, intentAddress, amount);
    }

    function depositToIntent(
        address user,
        address token,
        uint256 amount,
        address intentAddress,
        uint256 deadline,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) external nonReentrant {
        _verifyAndMarkIntent(user, token, amount, intentAddress, deadline, sigV, sigR, sigS);

        // Transfer tokens (assumes prior approval)
        IERC20(token).transferFrom(user, intentAddress, amount);

        emit IntentDeposit(user, intentAddress, amount);
    }

    function _verifyAndMarkIntent(
        address user,
        address token,
        uint256 amount,
        address intentAddress,
        uint256 deadline,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) internal {
        require(amount > 0, "Amount must be greater than 0");
        require(token != address(0), "Token must not be zero-address");
        require(block.timestamp <= deadline, "Intent expired");

        bytes32 intentHash = keccak256(abi.encode(INTENT_TYPEHASH, user, token, amount, intentAddress, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, intentHash));
        address recovered = ECDSA.recover(digest, sigV, sigR, sigS);
        require(recovered == user, "Invalid intent signature");

        require(!usedIntents[digest], "Intent already used");
        usedIntents[digest] = true;
    }
}
