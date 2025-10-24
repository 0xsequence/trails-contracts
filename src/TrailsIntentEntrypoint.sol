// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ITrailsIntentEntrypoint} from "./interfaces/ITrailsIntentEntrypoint.sol";

/// @title TrailsIntentEntrypoint
/// @author Miguel Mota
/// @notice A contract to facilitate deposits to intent addresses with off-chain signed intents.
contract TrailsIntentEntrypoint is ReentrancyGuard, ITrailsIntentEntrypoint {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    bytes32 public constant TRAILS_INTENT_TYPEHASH = keccak256(
        "TrailsIntent(address user,address token,uint256 amount,address intentAddress,uint256 deadline,uint256 chainId,uint256 nonce,uint256 feeAmount,address feeCollector)"
    );
    string public constant VERSION = "1";

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error InvalidAmount();
    error InvalidToken();
    error InvalidIntentAddress();
    error IntentExpired();
    error InvalidIntentSignature();
    error IntentAlreadyUsed();
    error InvalidChainId();
    error InvalidNonce();
    error PermitAmountMismatch();

    // -------------------------------------------------------------------------
    // Immutable Variables
    // -------------------------------------------------------------------------

    /// @notice EIP-712 domain separator used for intent signatures.
    bytes32 public immutable DOMAIN_SEPARATOR;

    // -------------------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------------------

    /// @notice Tracks whether an intent digest has been consumed to prevent replays.
    mapping(bytes32 => bool) public usedIntents;

    /// @notice Tracks nonce for each user to prevent replay attacks.
    mapping(address => uint256) public nonces;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

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

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /// @inheritdoc ITrailsIntentEntrypoint
    function depositToIntentWithPermit(
        address user,
        address token,
        uint256 amount,
        uint256 permitAmount,
        address intentAddress,
        uint256 deadline,
        uint256 nonce,
        uint256 feeAmount,
        address feeCollector,
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) external nonReentrant {
        _verifyAndMarkIntent(
            user, token, amount, intentAddress, deadline, nonce, feeAmount, feeCollector, sigV, sigR, sigS
        );

        // Validate permitAmount exactly matches the total required amount (deposit + fee)
        // This prevents permit/approval mismatches that could cause DoS or unexpected behavior
        unchecked {
            if (permitAmount != amount + feeAmount) revert PermitAmountMismatch();
        }

        IERC20Permit(token).permit(user, address(this), permitAmount, deadline, permitV, permitR, permitS);
        IERC20(token).safeTransferFrom(user, intentAddress, amount);

        // Pay fee if specified (fee token is same as deposit token)
        if (feeAmount > 0 && feeCollector != address(0)) {
            IERC20(token).safeTransferFrom(user, feeCollector, feeAmount);
            emit FeePaid(user, token, feeAmount, feeCollector);
        }

        emit IntentDeposit(user, intentAddress, amount);
    }

    /// @inheritdoc ITrailsIntentEntrypoint
    function depositToIntent(
        address user,
        address token,
        uint256 amount,
        address intentAddress,
        uint256 deadline,
        uint256 nonce,
        uint256 feeAmount,
        address feeCollector,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) external nonReentrant {
        _verifyAndMarkIntent(
            user, token, amount, intentAddress, deadline, nonce, feeAmount, feeCollector, sigV, sigR, sigS
        );

        IERC20(token).safeTransferFrom(user, intentAddress, amount);

        // Pay fee if specified (fee token is same as deposit token)
        if (feeAmount > 0 && feeCollector != address(0)) {
            IERC20(token).safeTransferFrom(user, feeCollector, feeAmount);
            emit FeePaid(user, token, feeAmount, feeCollector);
        }

        emit IntentDeposit(user, intentAddress, amount);
    }

    // -------------------------------------------------------------------------
    // Internal Functions
    // -------------------------------------------------------------------------

    /// forge-lint: disable-next-line(mixed-case-function)
    function _verifyAndMarkIntent(
        address user,
        address token,
        uint256 amount,
        address intentAddress,
        uint256 deadline,
        uint256 nonce,
        uint256 feeAmount,
        address feeCollector,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) internal {
        if (amount == 0) revert InvalidAmount();
        if (token == address(0)) revert InvalidToken();
        if (intentAddress == address(0)) revert InvalidIntentAddress();
        if (block.timestamp > deadline) revert IntentExpired();
        // Chain ID is already included in the signature, so we don't need to check it here
        // The signature verification will fail if the chain ID doesn't match
        if (nonce != nonces[user]) revert InvalidNonce();

        bytes32 _typehash = TRAILS_INTENT_TYPEHASH;
        bytes32 intentHash;
        // keccak256(abi.encode(TRAILS_INTENT_TYPEHASH, user, token, amount, intentAddress, deadline, chainId, nonce, feeAmount, feeCollector));
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, _typehash)
            mstore(add(ptr, 0x20), user)
            mstore(add(ptr, 0x40), token)
            mstore(add(ptr, 0x60), amount)
            mstore(add(ptr, 0x80), intentAddress)
            mstore(add(ptr, 0xa0), deadline)
            mstore(add(ptr, 0xc0), chainid())
            mstore(add(ptr, 0xe0), nonce)
            mstore(add(ptr, 0x100), feeAmount)
            mstore(add(ptr, 0x120), feeCollector)
            intentHash := keccak256(ptr, 0x140)
        }

        bytes32 _domainSeparator = DOMAIN_SEPARATOR;
        bytes32 digest;
        // keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, intentHash));
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x1901)
            mstore(add(ptr, 0x20), _domainSeparator)
            mstore(add(ptr, 0x40), intentHash)
            digest := keccak256(add(ptr, 0x1e), 0x42)
        }
        address recovered = ECDSA.recover(digest, sigV, sigR, sigS);
        if (recovered != user) revert InvalidIntentSignature();

        if (usedIntents[digest]) revert IntentAlreadyUsed();
        usedIntents[digest] = true;

        // Increment nonce for the user
        nonces[user]++;
    }
}
