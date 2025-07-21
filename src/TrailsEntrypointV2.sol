// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {RLPReader} from "./libraries/RLPReader.sol";
import {TrailsTxValidator} from "./libraries/TrailsTxValidator.sol";
import {TrailsPermitValidator} from "./libraries/TrailsPermitValidator.sol";
import {TrailsSignatureDecoder} from "./libraries/TrailsSignatureDecoder.sol";

/**
 * @title TrailsEntrypointV2
 * @author Shun Kakinoki
 * @notice A single entrypoint contract that accepts intents through ETH/ERC20 transfers with calldata suffixes.
 *         Implements a commit-prove pattern eliminating the need for approve steps, enabling 1-click crypto transactions.
 *         Inspired by Relay's suffix pattern and Klaster's transaction validation approach.
 */
contract TrailsEntrypointV2 is ReentrancyGuard {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------

    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for RLPReader.RLPItem[];
    using MerkleProof for bytes32[];
    using TrailsSignatureDecoder for bytes;
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    bytes32 constant TRANSFER_SIG = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    uint256 public constant MIN_INTENT_HASH_LENGTH = 32;
    uint256 public constant MAX_INTENT_DEADLINE = 86400; // 24 hours

    // EIP-712 constants for intent hashing
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant INTENT_TYPEHASH = keccak256(
        "Intent(address sender,address token,uint256 amount,uint256 destinationChain,address destinationAddress,bytes extraData,uint256 nonce,uint256 deadline)"
    );
    string public constant NAME = "TrailsEntrypointV2";
    string public constant VERSION = "1";

    bytes32 public immutable DOMAIN_SEPARATOR;

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    struct Intent {
        address sender;
        address token;
        uint256 amount;
        uint256 destinationChain;
        address destinationAddress;
        bytes extraData;
        uint256 nonce;
        uint256 deadline;
    }

    struct DepositState {
        address owner;
        address token;
        uint256 amount;
        uint8 status; // 0: Pending, 1: Proven, 2: Executed, 3: Failed
        Intent intent;
        uint256 timestamp;
        bytes32 commitmentHash;
    }

    enum IntentStatus {
        Pending,
        Proven,
        Executed,
        Failed
    }

    struct Call {
        address target;
        bytes data;
        uint256 value;
    }

    // -------------------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------------------

    mapping(bytes32 => DepositState) public deposits;
    mapping(bytes32 => bool) public processedTxs;
    mapping(address => uint256) public nonces;
    mapping(bytes32 => uint256) public intentExpirations;

    address public owner;
    bool public paused;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event IntentCommitted(bytes32 indexed intentHash, address indexed sender, Intent intent);
    event DepositReceived(bytes32 indexed intentHash, address indexed owner, address token, uint256 amount);
    event IntentProven(bytes32 indexed intentHash, address indexed prover, bytes signature);
    event IntentExecuted(bytes32 indexed intentHash, bool success, bytes returnData);
    event IntentExpired(bytes32 indexed intentHash, address indexed sender);
    event EmergencyWithdraw(bytes32 indexed intentHash, address indexed owner, uint256 amount);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error ContractPaused();
    error InvalidIntentHash();
    error IntentAlreadyExists();
    error IntentNotFound();
    error IntentHasExpired();
    error InvalidSender();
    error InvalidAmount();
    error InvalidToken();
    error InvalidSignature();
    error ExecutionFailed();
    error InvalidStatus();
    error Unauthorized();

    // -------------------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------------------

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier notPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier validIntentHash(bytes32 intentHash) {
        if (intentHash == bytes32(0)) revert InvalidIntentHash();
        _;
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION)), block.chainid, address(this))
        );
        owner = msg.sender;
        paused = false;
    }

    // -------------------------------------------------------------------------
    // Intent Hashing Functions
    // -------------------------------------------------------------------------

    function hashIntent(Intent memory intent) public view returns (bytes32) {
        if (intent.sender == address(0)) revert InvalidSender();
        if (intent.amount == 0) revert InvalidAmount();
        if (intent.deadline <= block.timestamp || intent.deadline > block.timestamp + MAX_INTENT_DEADLINE) {
            revert IntentHasExpired();
        }

        bytes32 structHash = keccak256(
            abi.encode(
                INTENT_TYPEHASH,
                intent.sender,
                intent.token,
                intent.amount,
                intent.destinationChain,
                intent.destinationAddress,
                keccak256(intent.extraData),
                intent.nonce,
                intent.deadline
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    function commitIntent(Intent memory intent) external notPaused returns (bytes32) {
        bytes32 intentHash = hashIntent(intent);

        if (deposits[intentHash].owner != address(0)) revert IntentAlreadyExists();
        if (nonces[intent.sender] != intent.nonce) revert InvalidSignature();

        // Initialize deposit state
        deposits[intentHash] = DepositState({
            owner: intent.sender,
            token: intent.token,
            amount: intent.amount,
            status: uint8(IntentStatus.Pending),
            intent: intent,
            timestamp: block.timestamp,
            commitmentHash: intentHash
        });

        nonces[intent.sender]++;
        intentExpirations[intentHash] = intent.deadline;

        emit IntentCommitted(intentHash, intent.sender, intent);
        return intentHash;
    }

    // -------------------------------------------------------------------------
    // Deposit Functions
    // -------------------------------------------------------------------------

    // Fallback for ETH deposits with calldata suffix containing intent hash
    fallback() external payable nonReentrant notPaused {
        if (msg.value == 0) revert InvalidAmount();
        if (msg.data.length < MIN_INTENT_HASH_LENGTH) revert InvalidIntentHash();

        // Extract the intent hash from the last 32 bytes of calldata
        bytes32 intentHash;
        assembly {
            intentHash := calldataload(sub(calldatasize(), 32))
        }

        if (intentHash == bytes32(0)) revert InvalidIntentHash();

        DepositState storage deposit = deposits[intentHash];
        if (deposit.owner == address(0)) revert IntentNotFound();
        if (deposit.owner != msg.sender) revert InvalidSender();
        if (deposit.token != address(0)) revert InvalidToken(); // Must be ETH
        if (deposit.amount != msg.value) revert InvalidAmount();
        if (block.timestamp > intentExpirations[intentHash]) revert IntentHasExpired();
        if (deposit.status != uint8(IntentStatus.Pending)) revert InvalidStatus();

        // Mark as deposit received
        emit DepositReceived(intentHash, msg.sender, address(0), msg.value);
    }

    receive() external payable {
        revert("ETH deposits must include intent hash in calldata - use fallback function");
    }

    function depositERC20WithIntent(bytes32 intentHash, address token, uint256 amount)
        external
        nonReentrant
        notPaused
        validIntentHash(intentHash)
    {
        DepositState storage deposit = deposits[intentHash];
        if (deposit.owner == address(0)) revert IntentNotFound();
        if (deposit.owner != msg.sender) revert InvalidSender();
        if (deposit.token != token) revert InvalidToken();
        if (deposit.amount != amount) revert InvalidAmount();
        if (block.timestamp > intentExpirations[intentHash]) revert IntentHasExpired();
        if (deposit.status != uint8(IntentStatus.Pending)) revert InvalidStatus();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit DepositReceived(intentHash, msg.sender, token, amount);
    }

    // -------------------------------------------------------------------------
    // Proof Functions
    // -------------------------------------------------------------------------

    function proveETHDeposit(bytes32 intentHash, bytes calldata signature)
        external
        nonReentrant
        notPaused
        validIntentHash(intentHash)
    {
        DepositState storage deposit = deposits[intentHash];
        if (deposit.owner == address(0)) revert IntentNotFound();
        if (deposit.status != uint8(IntentStatus.Pending)) revert InvalidStatus();
        if (block.timestamp > intentExpirations[intentHash]) revert IntentHasExpired();

        // Validate the signature proves the ETH deposit transaction
        TrailsSignatureDecoder.UserOpSignature memory decodedSig = signature.decodeSignature();

        if (decodedSig.signatureType == TrailsSignatureDecoder.UserOpSignatureType.ON_CHAIN) {
            TrailsTxValidator.validate(decodedSig.signature, intentHash, deposit.owner);
        } else {
            revert InvalidSignature();
        }

        // Mark as proven
        deposit.status = uint8(IntentStatus.Proven);
        emit IntentProven(intentHash, msg.sender, signature);
    }

    function proveERC20Deposit(bytes32 intentHash, bytes calldata signature)
        external
        nonReentrant
        notPaused
        validIntentHash(intentHash)
    {
        DepositState storage deposit = deposits[intentHash];
        if (deposit.owner == address(0)) revert IntentNotFound();
        if (deposit.status != uint8(IntentStatus.Pending)) revert InvalidStatus();
        if (block.timestamp > intentExpirations[intentHash]) revert IntentHasExpired();

        TrailsSignatureDecoder.UserOpSignature memory decodedSig = signature.decodeSignature();

        if (decodedSig.signatureType == TrailsSignatureDecoder.UserOpSignatureType.ON_CHAIN) {
            TrailsTxValidator.validate(decodedSig.signature, intentHash, deposit.owner);
        } else if (decodedSig.signatureType == TrailsSignatureDecoder.UserOpSignatureType.ERC20_PERMIT) {
            TrailsPermitValidator.validate(decodedSig.signature, address(this), intentHash, deposit.owner);
        } else {
            revert InvalidSignature();
        }

        // Transfer the ERC20 tokens to this contract if not already done
        if (deposit.token != address(0)) {
            IERC20(deposit.token).safeTransferFrom(deposit.owner, address(this), deposit.amount);
        }

        deposit.status = uint8(IntentStatus.Proven);
        emit IntentProven(intentHash, msg.sender, signature);
        emit DepositReceived(intentHash, deposit.owner, deposit.token, deposit.amount);
    }

    // -------------------------------------------------------------------------
    // Execution Functions
    // -------------------------------------------------------------------------

    function executeIntent(bytes32 intentHash, Call[] calldata calls)
        external
        nonReentrant
        notPaused
        validIntentHash(intentHash)
    {
        DepositState storage deposit = deposits[intentHash];
        if (deposit.status != uint8(IntentStatus.Proven)) revert InvalidStatus();
        if (block.timestamp > intentExpirations[intentHash]) revert IntentHasExpired();

        bool allSuccess = true;
        bytes memory lastReturnData;

        for (uint256 i = 0; i < calls.length; i++) {
            Call memory call = calls[i];
            (bool success, bytes memory returnData) = call.target.call{value: call.value}(call.data);

            if (!success) {
                allSuccess = false;
                lastReturnData = returnData;
                break;
            }
            lastReturnData = returnData;
        }

        if (allSuccess) {
            deposit.status = uint8(IntentStatus.Executed);
        } else {
            deposit.status = uint8(IntentStatus.Failed);
            // Refund on failure
            _refundDeposit(intentHash);
        }

        emit IntentExecuted(intentHash, allSuccess, lastReturnData);
    }

    // -------------------------------------------------------------------------
    // Emergency & Admin Functions
    // -------------------------------------------------------------------------

    function emergencyWithdraw(bytes32 intentHash) external validIntentHash(intentHash) {
        DepositState storage deposit = deposits[intentHash];
        if (deposit.owner != msg.sender) revert InvalidSender();
        if (deposit.status != uint8(IntentStatus.Failed) && block.timestamp <= intentExpirations[intentHash]) {
            revert InvalidStatus();
        }

        _refundDeposit(intentHash);
        emit EmergencyWithdraw(intentHash, msg.sender, deposit.amount);
    }

    function expireIntent(bytes32 intentHash) external validIntentHash(intentHash) {
        DepositState storage deposit = deposits[intentHash];
        if (block.timestamp <= intentExpirations[intentHash]) revert IntentHasExpired();
        if (deposit.status == uint8(IntentStatus.Executed)) revert InvalidStatus();

        _refundDeposit(intentHash);
        deposit.status = uint8(IntentStatus.Failed);
        emit IntentExpired(intentHash, deposit.owner);
    }

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidSender();
        owner = newOwner;
    }

    // -------------------------------------------------------------------------
    // View Functions
    // -------------------------------------------------------------------------

    function getDeposit(bytes32 intentHash) external view returns (DepositState memory) {
        return deposits[intentHash];
    }

    function validateIntent(Intent memory intent, bytes calldata signature) external view returns (bool) {
        bytes32 intentHash = hashIntent(intent);
        bytes32 messageHash = intentHash.toEthSignedMessageHash();
        address signer = messageHash.recover(signature);
        return signer == intent.sender;
    }

    // -------------------------------------------------------------------------
    // Internal Functions
    // -------------------------------------------------------------------------

    function _refundDeposit(bytes32 intentHash) internal {
        DepositState storage deposit = deposits[intentHash];

        if (deposit.token == address(0)) {
            // Refund ETH
            (bool success,) = payable(deposit.owner).call{value: deposit.amount}("");
            if (!success) revert ExecutionFailed();
        } else {
            // Refund ERC20
            IERC20(deposit.token).safeTransfer(deposit.owner, deposit.amount);
        }
    }
}
