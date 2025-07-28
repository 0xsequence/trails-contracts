// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {RLPReader} from "./libraries/RLPReader.sol";

// Placeholder interfaces for prototype (replace with actual in production)
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract TrailsEntrypointV2 {
    // -------------------------------------------------------------------------
    // Libraries
    // -------------------------------------------------------------------------

    using RLPReader for bytes;
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for RLPReader.RLPItem[];
    using MerkleProof for bytes32[];

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    bytes32 constant TRANSFER_SIG = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    struct DepositState {
        address owner;
        address token;
        uint256 amount;
        uint8 status; // 0: Pending, 1: Bridged, 2: Completed
    }

    // -------------------------------------------------------------------------
    // Mappings
    // -------------------------------------------------------------------------

    mapping(bytes32 => DepositState) public deposits;
    mapping(bytes32 => bool) public processedTxs;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event DepositProved(bytes32 indexed intentHash, address owner, address token, uint256 amount);
    event ETHDepositReceived(bytes32 indexed intentHash, address owner, uint256 amount);
    event IntentExecuted(bytes32 indexed intentHash, uint8 status);

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    // Fallback for ETH deposits with calldata suffix (intent descriptor)
    fallback() external payable {
        require(msg.value > 0, "No ETH sent");
        require(msg.data.length > 0, "No intent descriptor");

        bytes32 intentHash = keccak256(msg.data);

        deposits[intentHash].owner = msg.sender;
        deposits[intentHash].token = address(0);
        deposits[intentHash].amount += msg.value;
        deposits[intentHash].status = 0;

        emit ETHDepositReceived(intentHash, msg.sender, msg.value);
    }

    receive() external payable {
        revert("Use fallback with calldata for intent");
    }

    function proveERC20Deposit(
        uint256 blockNum,
        bytes calldata headerRLP,
        bytes32[] calldata merkleProofTx,
        bytes calldata txRLP,
        bytes32[] calldata merkleProofReceipt,
        bytes calldata receiptRLP
    ) external {
        require(block.number - 256 < blockNum && blockNum < block.number, "Invalid block number");

        bytes32 headerHash = keccak256(headerRLP);
        require(headerHash == blockhash(blockNum), "Invalid header hash");

        RLPReader.RLPItem memory rlpHeader = headerRLP.toRlpItem();
        RLPReader.RLPItem[] memory headerItems = rlpHeader.toList();
        bytes32 txRoot = headerItems[4].toBytes32();
        bytes32 receiptRoot = headerItems[5].toBytes32();

        bytes32 txLeaf = keccak256(txRLP);
        require(merkleProofTx.verify(txRoot, txLeaf), "Invalid tx proof");

        RLPReader.RLPItem memory rlpTx = txRLP.toRlpItem();
        RLPReader.RLPItem[] memory txItems = rlpTx.toList();
        address token = txItems[3].toAddress();
        uint256 value = txItems[4].toUint();
        require(value == 0, "Non-zero value for ERC20");
        bytes memory input = txItems[5].toBytes();

        require(input.length >= 68, "Input too short");

        bytes4 selector;
        assembly {
            selector := mload(add(input, 32))
        }
        selector = bytes4(selector);
        require(selector == 0xa9059cbb, "Not transfer");

        address recipient;
        assembly {
            recipient := mload(add(input, 36))
        }
        require(recipient == address(this), "Not to entrypoint");

        uint256 amount;
        assembly {
            amount := mload(add(input, 68))
        }

        require(input.length > 68, "No suffix");
        bytes memory suffix = new bytes(input.length - 68);
        assembly {
            calldatacopy(add(suffix, 32), add(add(input, 32), 68), sub(mload(input), 68))
        }
        bytes32 intentHash = keccak256(suffix);

        bytes32 receiptLeaf = keccak256(receiptRLP);
        require(merkleProofReceipt.verify(receiptRoot, receiptLeaf), "Invalid receipt proof");

        RLPReader.RLPItem memory rlpReceipt = receiptRLP.toRlpItem();
        RLPReader.RLPItem[] memory receiptItems = rlpReceipt.toList();
        RLPReader.RLPItem memory logsItem = receiptItems[3];
        RLPReader.RLPItem[] memory logs = logsItem.toList();

        require(logs.length > 0, "No logs");
        RLPReader.RLPItem[] memory logItems = logs[0].toList(); // Assume first log; production: loop to find
        address logAddress = logItems[0].toAddress();
        require(logAddress == token, "Log address mismatch");

        RLPReader.RLPItem[] memory topics = logItems[1].toList();
        require(topics.length == 3, "Invalid topics count");
        require(topics[0].toBytes32() == TRANSFER_SIG, "Not Transfer event");

        address from = address(uint160(uint256(topics[1].toBytes32())));
        address to = address(uint160(uint256(topics[2].toBytes32())));
        require(to == address(this), "Log to mismatch");

        bytes memory logData = logItems[2].toBytes();
        uint256 logAmount;
        assembly {
            logAmount := mload(add(logData, 32))
        }
        require(logAmount == amount, "Amount mismatch");

        bytes32 txHash = keccak256(txRLP);
        require(!processedTxs[txHash], "Tx already processed");
        processedTxs[txHash] = true;

        deposits[intentHash].owner = from;
        deposits[intentHash].token = token;
        deposits[intentHash].amount += logAmount;
        deposits[intentHash].status = 0;

        emit DepositProved(intentHash, from, token, logAmount);
    }

    // -------------------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------------------

    struct Call {
        address target;
        bytes calldata_;
        uint256 value;
    }

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    // Execute origin intent (generic arbitrary multicall; permissionless)
    // calls: Array of calls to execute in sequence (e.g., swap, bridge)
    function executeOrigin(bytes32 intentHash, Call[] calldata calls) external {
        DepositState storage deposit = deposits[intentHash];
        require(deposit.status == 0, "Not pending");

        for (uint256 i = 0; i < calls.length; i++) {
            Call memory c = calls[i];
            (bool success,) = c.target.call{value: c.value}(c.calldata_);
            require(success, "Call failed");
        }

        deposit.status = 1;
        emit IntentExecuted(intentHash, 1);
    }
}
