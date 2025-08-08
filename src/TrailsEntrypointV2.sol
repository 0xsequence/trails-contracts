// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
contract TrailsEntrypointV2 {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------

    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for RLPReader.RLPItem[];
    using TrailsSignatureDecoder for bytes;
    using SafeERC20 for IERC20;

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
        "Intent(address sender,address token,uint256 amount,Call[] calls,uint256 nonce,uint256 deadline)Call(address target,bytes data,uint256 value)"
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
        Call[] calls; // The exact calls to execute - committed to by user
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
        Pending, // Relayer committed, ready for proof
        Proven, // Proof validated, ready for execution
        Executed, // Successfully executed
        Failed // Failed or expired

    }

    enum TransferStatus {
        Uncommitted, // User transferred, waiting for relayer
        Committed, // Relayer committed the intent
        Expired // Transfer expired before commitment

    }

    struct Call {
        address target;
        bytes data;
        uint256 value;
    }

    // -------------------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------------------

    // Track user transfers before relayer commits
    struct PendingTransfer {
        address sender;
        address token;
        uint256 amount;
        uint256 timestamp;
        bytes intentData; // Raw intent data from calldata
        bool committed; // Whether relayer has committed this transfer
    }

    mapping(bytes32 => DepositState) public deposits;
    mapping(bytes32 => PendingTransfer) public pendingTransfers; // transferId -> PendingTransfer
    mapping(bytes32 => bool) public processedTxs;
    mapping(address => uint256) public nonces;
    mapping(bytes32 => uint256) public intentExpirations;
    mapping(bytes32 => bytes32) public transferToIntent; // transferId -> intentHash

    address public owner;
    bool public paused;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event TransferReceived(
        bytes32 indexed transferId, address indexed sender, address token, uint256 amount, bytes intentData
    );
    event IntentCommitted(
        bytes32 indexed intentHash, bytes32 indexed transferId, address indexed sender, Intent intent
    );
    event IntentProven(bytes32 indexed intentHash, address indexed prover, bytes signature);
    event IntentExecuted(bytes32 indexed intentHash, bool success, bytes returnData);
    event IntentExpired(bytes32 indexed intentHash, address indexed sender);
    event TransferExpired(bytes32 indexed transferId, address indexed sender);
    event EmergencyWithdraw(bytes32 indexed intentHash, address indexed owner, uint256 amount);

    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error ContractPaused();
    error InvalidIntentHash();
    error InvalidTransferId();
    error IntentAlreadyExists();
    error IntentNotFound();
    error TransferNotFound();
    error TransferAlreadyCommitted();
    error IntentHasExpired();
    error TransferHasExpired();
    error InvalidSender();
    error InvalidAmount();
    error InvalidToken();
    error InvalidSignature();
    error ExecutionFailed();
    error InvalidStatus();
    error Unauthorized();
    error InvalidIntentData();

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

    modifier validTransferId(bytes32 transferId) {
        if (transferId == bytes32(0)) revert InvalidTransferId();
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

        // Hash the calls array
        bytes32 callsHash = keccak256(abi.encode(intent.calls));

        bytes32 structHash = keccak256(
            abi.encode(
                INTENT_TYPEHASH, intent.sender, intent.token, intent.amount, callsHash, intent.nonce, intent.deadline
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    // Step 2: Relayer commits/verifies intent based on user's transfer
    function commitIntent(bytes32 transferId, Intent memory intent) external notPaused returns (bytes32) {
        PendingTransfer storage transfer = pendingTransfers[transferId];
        if (transfer.sender == address(0)) revert TransferNotFound();
        if (transfer.committed) revert TransferAlreadyCommitted();
        if (block.timestamp > transfer.timestamp + MAX_INTENT_DEADLINE) revert TransferHasExpired();

        // Verify intent matches the transfer
        if (intent.sender != transfer.sender) revert InvalidSender();
        if (intent.token != transfer.token) revert InvalidToken();
        if (intent.amount != transfer.amount) revert InvalidAmount();
        if (nonces[intent.sender] != intent.nonce) revert InvalidSignature();

        // Validate intent data matches what user sent
        // Intent hash calculated for validation purposes (can be used off-chain)
        // Skipping on-chain intentData validation to reduce contract size

        bytes32 intentHash = hashIntent(intent);
        if (deposits[intentHash].owner != address(0)) revert IntentAlreadyExists();

        // Mark transfer as committed
        transfer.committed = true;
        transferToIntent[transferId] = intentHash;

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

        emit IntentCommitted(intentHash, transferId, intent.sender, intent);
        return intentHash;
    }

    // Combined function: commit intent and immediately mark as proven for testing/simple flows
    function commitAndProveIntent(bytes32 transferId, Intent memory intent) external notPaused returns (bytes32) {
        PendingTransfer storage transfer = pendingTransfers[transferId];
        if (transfer.sender == address(0)) revert TransferNotFound();
        if (transfer.committed) revert TransferAlreadyCommitted();
        if (block.timestamp > transfer.timestamp + MAX_INTENT_DEADLINE) revert TransferHasExpired();

        // Verify intent matches the transfer
        if (intent.sender != transfer.sender) revert InvalidSender();
        if (intent.token != transfer.token) revert InvalidToken();
        if (intent.amount != transfer.amount) revert InvalidAmount();
        if (nonces[intent.sender] != intent.nonce) revert InvalidSignature();

        bytes32 intentHash = hashIntent(intent);
        if (deposits[intentHash].owner != address(0)) revert IntentAlreadyExists();

        // Mark transfer as committed
        transfer.committed = true;
        transferToIntent[transferId] = intentHash;

        // Initialize deposit state with Proven status
        deposits[intentHash] = DepositState({
            owner: intent.sender,
            token: intent.token,
            amount: intent.amount,
            status: uint8(IntentStatus.Proven), // Start as proven
            intent: intent,
            timestamp: block.timestamp,
            commitmentHash: intentHash
        });

        nonces[intent.sender]++;
        intentExpirations[intentHash] = intent.deadline;

        emit IntentCommitted(intentHash, transferId, intent.sender, intent);
        emit IntentProven(intentHash, msg.sender, "");
        return intentHash;
    }

    // Ultimate function: commit + prove + execute intent in one call
    function commitProveAndExecuteIntent(bytes32 transferId, Intent memory intent)
        external
        notPaused
        returns (bytes32)
    {
        PendingTransfer storage transfer = pendingTransfers[transferId];
        if (transfer.sender == address(0)) revert TransferNotFound();
        if (transfer.committed) revert TransferAlreadyCommitted();
        if (block.timestamp > transfer.timestamp + MAX_INTENT_DEADLINE) revert TransferHasExpired();

        // Verify intent matches the transfer
        if (intent.sender != transfer.sender) revert InvalidSender();
        if (intent.token != transfer.token) revert InvalidToken();
        if (intent.amount != transfer.amount) revert InvalidAmount();
        if (nonces[intent.sender] != intent.nonce) revert InvalidSignature();

        bytes32 intentHash = hashIntent(intent);
        if (deposits[intentHash].owner != address(0)) revert IntentAlreadyExists();

        // Mark transfer as committed
        transfer.committed = true;
        transferToIntent[transferId] = intentHash;

        // Initialize deposit state with Proven status
        deposits[intentHash] = DepositState({
            owner: intent.sender,
            token: intent.token,
            amount: intent.amount,
            status: uint8(IntentStatus.Proven), // Start as proven
            intent: intent,
            timestamp: block.timestamp,
            commitmentHash: intentHash
        });

        nonces[intent.sender]++;
        intentExpirations[intentHash] = intent.deadline;

        emit IntentCommitted(intentHash, transferId, intent.sender, intent);
        emit IntentProven(intentHash, msg.sender, "");

        // Execute immediately using calls from intent
        bool allSuccess = true;
        bytes memory lastReturnData;

        for (uint256 i = 0; i < intent.calls.length; i++) {
            Call memory call = intent.calls[i];
            (bool success, bytes memory returnData) = call.target.call{value: call.value}(call.data);

            if (!success) {
                allSuccess = false;
                lastReturnData = returnData;
                break;
            }
            lastReturnData = returnData;
        }

        if (allSuccess) {
            deposits[intentHash].status = uint8(IntentStatus.Executed);
        } else {
            deposits[intentHash].status = uint8(IntentStatus.Failed);
            // Refund on failure
            _refundDeposit(intentHash);
        }

        emit IntentExecuted(intentHash, allSuccess, lastReturnData);
        return intentHash;
    }

    // -------------------------------------------------------------------------
    // Deposit Functions
    // -------------------------------------------------------------------------

    // Fallback for ETH transfers with calldata containing intent data
    // Step 1: User makes 1-click transfer with intent data in calldata
    fallback() external payable notPaused {
        if (msg.value == 0) revert InvalidAmount();
        if (msg.data.length == 0) revert InvalidIntentData();

        // Generate unique transfer ID from tx hash components
        bytes32 transferId = keccak256(
            abi.encodePacked(
                block.timestamp,
                msg.sender,
                msg.value,
                msg.data,
                tx.gasprice // Add uniqueness
            )
        );

        // Store the pending transfer with intent data
        pendingTransfers[transferId] = PendingTransfer({
            sender: msg.sender,
            token: address(0), // ETH
            amount: msg.value,
            timestamp: block.timestamp,
            intentData: msg.data, // Store raw intent data from user
            committed: false
        });

        emit TransferReceived(transferId, msg.sender, address(0), msg.value, msg.data);
    }

    receive() external payable {
        revert("ETH transfers must include intent data in calldata - use fallback function");
    }

    // Step 1: User makes 1-click ERC20 transfer with intent data
    function depositERC20WithIntent(address token, uint256 amount, bytes calldata intentData) external notPaused {
        if (amount == 0) revert InvalidAmount();
        if (token == address(0)) revert InvalidToken();
        if (intentData.length == 0) revert InvalidIntentData();

        // Generate unique transfer ID
        bytes32 transferId =
            keccak256(abi.encodePacked(block.timestamp, msg.sender, token, amount, intentData, tx.gasprice));

        // Store the pending transfer
        pendingTransfers[transferId] = PendingTransfer({
            sender: msg.sender,
            token: token,
            amount: amount,
            timestamp: block.timestamp,
            intentData: intentData,
            committed: false
        });

        // Transfer tokens to contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        emit TransferReceived(transferId, msg.sender, token, amount, intentData);
    }

    // -------------------------------------------------------------------------
    // Proof Functions
    // -------------------------------------------------------------------------

    function proveETHDeposit(bytes32 intentHash, bytes calldata signature)
        external
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
        // DepositReceived event removed - transfer already happened in Step 1
    }

    // -------------------------------------------------------------------------
    // Execution Functions
    // -------------------------------------------------------------------------

    function executeIntent(bytes32 intentHash) external notPaused validIntentHash(intentHash) {
        DepositState storage deposit = deposits[intentHash];
        if (deposit.status != uint8(IntentStatus.Proven)) revert InvalidStatus();
        if (block.timestamp > intentExpirations[intentHash]) revert IntentHasExpired();

        bool allSuccess = true;
        bytes memory lastReturnData;

        // Execute calls from the committed intent
        for (uint256 i = 0; i < deposit.intent.calls.length; i++) {
            Call memory call = deposit.intent.calls[i];
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

    // Allow users to reclaim transfers that weren't committed by relayers
    function expireTransfer(bytes32 transferId) external {
        PendingTransfer storage transfer = pendingTransfers[transferId];
        if (transfer.sender == address(0)) revert TransferNotFound();
        if (transfer.sender != msg.sender) revert InvalidSender();
        if (transfer.committed) revert TransferAlreadyCommitted();
        if (block.timestamp <= transfer.timestamp + MAX_INTENT_DEADLINE) revert TransferHasExpired();

        // Refund the transfer
        if (transfer.token == address(0)) {
            // Refund ETH
            (bool success,) = payable(transfer.sender).call{value: transfer.amount}("");
            if (!success) revert ExecutionFailed();
        } else {
            // Refund ERC20
            IERC20(transfer.token).safeTransfer(transfer.sender, transfer.amount);
        }

        // Mark as expired
        delete pendingTransfers[transferId];
        emit TransferExpired(transferId, transfer.sender);
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

    function getPendingTransfer(bytes32 transferId) external view returns (PendingTransfer memory) {
        return pendingTransfers[transferId];
    }

    function getTransferIntent(bytes32 transferId) external view returns (bytes32) {
        return transferToIntent[transferId];
    }

    // validateIntent removed to reduce code size

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
