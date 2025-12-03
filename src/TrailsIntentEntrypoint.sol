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

    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant EIP712_DOMAIN_NAME = keccak256(bytes("TrailsIntentEntrypoint"));
    bytes32 private constant EIP712_DOMAIN_VERSION = keccak256(bytes(VERSION));

    // Mask to ensure deadline hash is always in the future
    uint256 private constant DEADLINE_MASK = 0xff00000000000000000000000000000000000000000000000000000000000000;

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error InvalidAmount();
    error InvalidToken();
    error InvalidIntentAddress();
    error IntentExpired();
    error InvalidIntentSignature();
    error InvalidNonce();
    error InvalidFeeParameters();

    // -------------------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------------------

    /// @notice Tracks nonce for each user to prevent replay attacks.
    mapping(address => uint256) public nonces;

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    /// @inheritdoc ITrailsIntentEntrypoint
    function DOMAIN_SEPARATOR() public view returns (bytes32 _domainSeparator) {
        return keccak256(
            abi.encode(EIP712_DOMAIN_TYPEHASH, EIP712_DOMAIN_NAME, EIP712_DOMAIN_VERSION, block.chainid, address(this))
        );
    }

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
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) external nonReentrant {
        // Validate intent parameters and increment nonce (digest validation is nested within permit execution)
        bytes32 intentDigest =
            _prepareIntentUsage(user, token, amount, intentAddress, deadline, nonce, feeAmount, feeCollector);
        uint256 permitDeadline = uint256(intentDigest) | DEADLINE_MASK;

        // Execute permit
        IERC20Permit(token).permit(user, address(this), permitAmount, permitDeadline, sigV, sigR, sigS);

        _processDeposit(user, token, amount, intentAddress, feeAmount, feeCollector);
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
        bytes32 intentDigest = _prepareIntentUsage(
            user, token, amount, intentAddress, deadline, nonce, feeAmount, feeCollector
        );

        _verifyIntentSignature(intentDigest, sigV, sigR, sigS, user);

        _processDeposit(user, token, amount, intentAddress, feeAmount, feeCollector);
    }

    // -------------------------------------------------------------------------
    // Internal Functions
    // -------------------------------------------------------------------------

    /// @notice Prepares intent usage by validating parameters, building intent digest, and incrementing nonce
    /// @dev If deadline is 0, skips expiration check (used for permit flow where deadline is computed)
    /// @param user The user making the deposit
    /// @param token The token to deposit
    /// @param amount The amount to deposit
    /// @param intentAddress The intent address to deposit to
    /// @param deadline The intent deadline (0 to skip expiration check)
    /// @param nonce The nonce for this user
    /// @param feeAmount The amount of fee to pay
    /// @param feeCollector The address to receive the fee
    /// @return intentDigest The EIP-712 digest of the intent message
    function _prepareIntentUsage(
        address user,
        address token,
        uint256 amount,
        address intentAddress,
        uint256 deadline,
        uint256 nonce,
        uint256 feeAmount,
        address feeCollector
    ) internal returns (bytes32 intentDigest) {
        // Validate parameters
        if (amount == 0) revert InvalidAmount();
        if (token == address(0)) revert InvalidToken();
        if (intentAddress == address(0)) revert InvalidIntentAddress();
        if (block.timestamp > deadline) revert IntentExpired();
        if (nonce != nonces[user]) revert InvalidNonce();

        // Build intent hash
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

        // Build intent digest
        bytes32 _domainSeparator = DOMAIN_SEPARATOR();
        // keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, intentHash));
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x1901)
            mstore(add(ptr, 0x20), _domainSeparator)
            mstore(add(ptr, 0x40), intentHash)
            intentDigest := keccak256(add(ptr, 0x1e), 0x42)
        }

        // Increment nonce for the user
        nonces[user]++;
    }

    /// @notice Verifies that the intent signature is valid
    /// @param intentDigest The EIP-712 digest of the intent message
    /// @param sigV The signature v component
    /// @param sigR The signature r component
    /// @param sigS The signature s component
    /// @param expectedUser The expected user address that signed the intent
    function _verifyIntentSignature(bytes32 intentDigest, uint8 sigV, bytes32 sigR, bytes32 sigS, address expectedUser)
        internal
        pure
    {
        address recovered = ECDSA.recover(intentDigest, sigV, sigR, sigS);
        if (recovered != expectedUser) revert InvalidIntentSignature();
    }

    function _processDeposit(
        address user,
        address token,
        uint256 amount,
        address intentAddress,
        uint256 feeAmount,
        address feeCollector
    ) internal {
        IERC20(token).safeTransferFrom(user, intentAddress, amount);

        // Pay fee if specified (fee token is same as deposit token)
        bool feeAmountSupplied = feeAmount > 0;
        bool feeCollectorSupplied = feeCollector != address(0);
        if (feeAmountSupplied != feeCollectorSupplied) {
            // Must supply both feeAmount and feeCollector, or neither
            revert InvalidFeeParameters();
        }
        if (feeAmountSupplied && feeCollectorSupplied) {
            IERC20(token).safeTransferFrom(user, feeCollector, feeAmount);
            emit FeePaid(user, token, feeAmount, feeCollector);
        }

        emit IntentDeposit(user, intentAddress, amount);
    }
}
