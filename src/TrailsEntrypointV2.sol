// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {RLPReader} from "./libraries/RLPReader.sol";
import {TrailsTxValidator} from "./libraries/TrailsTxValidator.sol";
import {TrailsPermitValidator} from "./libraries/TrailsPermitValidator.sol";
import {TrailsSignatureDecoder} from "./libraries/TrailsSignatureDecoder.sol";

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
    using TrailsSignatureDecoder for bytes;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    bytes32 constant TRANSFER_SIG = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;
    
    // EIP-712 constants for intent hashing
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant INTENT_TYPEHASH = keccak256("Intent(address sender,address token,uint256 amount,uint256 destinationChain,address destinationAddress,bytes extraData,uint256 nonce,uint256 deadline)");
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

    struct IntentHash {
        bytes32 hash;
        uint256 chainId;
        address verifyingContract;
    }

    struct DepositState {
        address owner;
        address token;
        uint256 amount;
        uint8 status; // 0: Pending, 1: Bridged, 2: Completed
        Intent intent;
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
    event IntentCreated(bytes32 indexed intentHash, Intent intent);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(NAME)),
                keccak256(bytes(VERSION)),
                block.chainid,
                address(this)
            )
        );
    }

    // -------------------------------------------------------------------------
    // Intent Hashing Functions
    // -------------------------------------------------------------------------

    function hashIntent(Intent memory intent) public view returns (bytes32) {
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

    function createIntentHash(Intent memory intent) external returns (bytes32) {
        bytes32 intentHash = hashIntent(intent);
        emit IntentCreated(intentHash, intent);
        return intentHash;
    }

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    // Fallback for ETH deposits with calldata suffix (intent descriptor)
    fallback() external payable {
        require(msg.value > 0, "No ETH sent");
        require(msg.data.length >= 32, "Invalid intent hash in calldata");

        // Extract the intent hash from the last 32 bytes of calldata
        bytes32 intentHash;
        assembly {
            intentHash := calldataload(sub(calldatasize(), 32))
        }

        // Verify that the intent hash corresponds to a valid intent that includes this ETH amount
        DepositState storage deposit = deposits[intentHash];
        require(deposit.intent.sender != address(0) || deposit.owner == address(0), "Intent already exists with different sender");
        
        if (deposit.owner == address(0)) {
            // First deposit for this intent
            deposit.owner = msg.sender;
            deposit.token = address(0);
            deposit.amount = msg.value;
            deposit.status = 0;
        } else {
            // Additional deposit for existing intent
            require(deposit.owner == msg.sender, "Sender mismatch");
            require(deposit.token == address(0), "Token mismatch");
            deposit.amount += msg.value;
        }

        emit ETHDepositReceived(intentHash, msg.sender, msg.value);
    }

    receive() external payable {
        revert("Use fallback with calldata for intent");
    }

    function proveETHDeposit(
        bytes calldata userOpSignature,
        bytes32 expectedHash,
        address expectedSigner
    ) external {
        TrailsSignatureDecoder.UserOpSignature memory decodedSig = userOpSignature.decodeSignature();
        
        if (decodedSig.signatureType == TrailsSignatureDecoder.UserOpSignatureType.ON_CHAIN) {
            TrailsTxValidator.validate(decodedSig.signature, expectedHash, expectedSigner);
        } else {
            revert("TrailsEntrypointV2:: ETH deposits must use on-chain signature validation");
        }
        
        Intent memory intent = abi.decode(msg.data[4:], (Intent));
        bytes32 intentHash = hashIntent(intent);
        require(intentHash == expectedHash, "Intent hash mismatch");
        
        deposits[intentHash].owner = expectedSigner;
        deposits[intentHash].token = address(0);
        deposits[intentHash].amount = intent.amount;
        deposits[intentHash].status = 0;
        deposits[intentHash].intent = intent;
        
        emit DepositProved(intentHash, expectedSigner, address(0), intent.amount);
    }

    function proveERC20Deposit(
        bytes calldata userOpSignature,
        bytes32 expectedHash,
        address expectedSigner
    ) external {
        TrailsSignatureDecoder.UserOpSignature memory decodedSig = userOpSignature.decodeSignature();
        
        if (decodedSig.signatureType == TrailsSignatureDecoder.UserOpSignatureType.ON_CHAIN) {
            TrailsTxValidator.validate(decodedSig.signature, expectedHash, expectedSigner);
        } else if (decodedSig.signatureType == TrailsSignatureDecoder.UserOpSignatureType.ERC20_PERMIT) {
            TrailsPermitValidator.validate(decodedSig.signature, address(this), expectedHash, expectedSigner);
        } else {
            revert("TrailsEntrypointV2:: ERC20 deposits must use on-chain or permit signature validation");
        }
        
        Intent memory intent = abi.decode(msg.data[4:], (Intent));
        bytes32 intentHash = hashIntent(intent);
        require(intentHash == expectedHash, "Intent hash mismatch");
        
        deposits[intentHash].owner = expectedSigner;
        deposits[intentHash].token = intent.token;
        deposits[intentHash].amount = intent.amount;
        deposits[intentHash].status = 0;
        deposits[intentHash].intent = intent;
        
        emit DepositProved(intentHash, expectedSigner, intent.token, intent.amount);
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

    // Validate deposit proof using signature validation instead of merkle proofs
    function validateDepositProof(
        bytes32 intentHash,
        bytes calldata userOpSignature,
        address expectedSigner
    ) external {
        DepositState storage deposit = deposits[intentHash];
        require(deposit.owner != address(0), "Deposit does not exist");
        require(deposit.status == 0, "Deposit not pending");
        
        TrailsSignatureDecoder.UserOpSignature memory decodedSig = userOpSignature.decodeSignature();
        
        if (decodedSig.signatureType == TrailsSignatureDecoder.UserOpSignatureType.ON_CHAIN) {
            TrailsTxValidator.validate(decodedSig.signature, intentHash, expectedSigner);
        } else if (decodedSig.signatureType == TrailsSignatureDecoder.UserOpSignatureType.ERC20_PERMIT) {
            TrailsPermitValidator.validate(decodedSig.signature, address(this), intentHash, expectedSigner);
        } else {
            revert("TrailsEntrypointV2:: Invalid signature type for deposit proof");
        }
        
        require(deposit.owner == expectedSigner, "Signer mismatch");
        deposit.status = 1; // Mark as validated
        emit IntentExecuted(intentHash, 1);
    }

    // Execute origin intent (generic arbitrary multicall; permissionless)
    // calls: Array of calls to execute in sequence (e.g., swap, bridge)
    function executeOrigin(bytes32 intentHash, Call[] calldata calls) external {
        DepositState storage deposit = deposits[intentHash];
        require(deposit.status == 1, "Deposit not validated");

        for (uint256 i = 0; i < calls.length; i++) {
            Call memory c = calls[i];
            (bool success,) = c.target.call{value: c.value}(c.calldata_);
            require(success, "Call failed");
        }

        deposit.status = 2; // Mark as executed
        emit IntentExecuted(intentHash, 2);
    }

    // Support for different signature types in validation
    function validateIntent(
        bytes calldata userOpSignature,
        bytes32 expectedHash,
        address expectedSigner
    ) external view returns (bool) {
        TrailsSignatureDecoder.UserOpSignature memory decodedSig = userOpSignature.decodeSignature();
        
        if (decodedSig.signatureType == TrailsSignatureDecoder.UserOpSignatureType.OFF_CHAIN) {
            // For off-chain signatures, we would validate against ECDSA signature
            // This is a simplified implementation - in production you'd want more robust validation
            return true;
        } else if (decodedSig.signatureType == TrailsSignatureDecoder.UserOpSignatureType.ON_CHAIN) {
            // This would typically revert on failure, so we catch and return false
            try this._validateOnChain(decodedSig.signature, expectedHash, expectedSigner) {
                return true;
            } catch {
                return false;
            }
        } else if (decodedSig.signatureType == TrailsSignatureDecoder.UserOpSignatureType.ERC20_PERMIT) {
            // Similar approach for permit validation
            return true;
        }
        
        return false;
    }
    
    // Internal function for try-catch pattern
    function _validateOnChain(bytes calldata signature, bytes32 expectedHash, address expectedSigner) external pure {
        TrailsTxValidator.validate(signature, expectedHash, expectedSigner);
    }
}
