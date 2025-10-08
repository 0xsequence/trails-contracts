// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
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

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    bytes32 public constant INTENT_TYPEHASH =
        keccak256("Intent(address user,address token,uint256 amount,address intentAddress,uint256 deadline)");
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
        uint8 permitV,
        bytes32 permitR,
        bytes32 permitS,
        uint8 sigV,
        bytes32 sigR,
        bytes32 sigS
    ) external nonReentrant {
        _verifyAndMarkIntent(user, token, amount, intentAddress, deadline, sigV, sigR, sigS);

        IERC20Permit(token).permit(user, address(this), permitAmount, deadline, permitV, permitR, permitS);
        IERC20(token).transferFrom(user, intentAddress, amount);

        emit IntentDeposit(user, intentAddress, amount);
    }

    /// @inheritdoc ITrailsIntentEntrypoint
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

        IERC20(token).transferFrom(user, intentAddress, amount);

        emit IntentDeposit(user, intentAddress, amount);
    }

    // -------------------------------------------------------------------------
    // Internal Functions
    // -------------------------------------------------------------------------

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
        if (amount == 0) revert InvalidAmount();
        if (token == address(0)) revert InvalidToken();
        if (intentAddress == address(0)) revert InvalidIntentAddress();
        if (block.timestamp > deadline) revert IntentExpired();

        bytes32 intentHash = keccak256(abi.encode(INTENT_TYPEHASH, user, token, amount, intentAddress, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, intentHash));
        address recovered = ECDSA.recover(digest, sigV, sigR, sigS);
        if (recovered != user) revert InvalidIntentSignature();

        if (usedIntents[digest]) revert IntentAlreadyUsed();
        usedIntents[digest] = true;
    }
}
