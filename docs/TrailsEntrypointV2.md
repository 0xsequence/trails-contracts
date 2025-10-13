# TrailsEntrypointV2 Technical Specification

## Overview

TrailsEntrypointV2 is a revolutionary single entrypoint contract that enables truly 1-click crypto transactions through a unique reversed flow: users make transfers first with intent data, then relayers detect and commit these intents. This eliminates all user complexity - no approvals, no intent management, just a single transfer. The system monitors user transfers and handles all backend complexity through relayers. Inspired by Relay's suffix pattern and Klaster's transaction validation approach.

## Architecture

### Core Innovation

The contract combines:
- **Single Entrypoint**: All intents flow through one contract
- **Transfer Suffix Pattern**: ETH/ERC20 transfers carry intent hash in calldata suffix
- **Relayer-Operated Architecture**: Users only transfer, relayers handle everything else
- **True 1-Click Experience**: No approvals, no intent management for users
- **Commit-Prove Pattern**: Two-phase validation eliminating approve step
- **Intent-Based Architecture**: Generic cross-chain operations via structured intents

### Key Components

1. **Relayer-Operated Intent Management**: EIP-712 structured intent hashing with nonce-based anti-replay (handled by relayers)
2. **1-Click Deposit Handling**: ETH via fallback function, ERC20 via dedicated functions (user's only action)
3. **Automated Proof Validation**: On-chain transaction validation using signature proofs (relayer responsibility)
4. **Generic Execution**: Arbitrary multicall support for bridges, swaps, and DeFi operations (relayer-executed)
5. **Safety Mechanisms**: Emergency withdrawals, intent expiration, and pause functionality
6. **True User Abstraction**: Users only transfer, relayers handle all complexity

## Technical Specification

### Contract Details

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract TrailsEntrypointV2 is ReentrancyGuard {
    // Inherits from OpenZeppelin's ReentrancyGuard for protection
}
```

### Core Data Structures

#### Intent Structure
```solidity
struct Intent {
    address sender;              // Intent originator
    address token;               // Token address (address(0) for ETH)
    uint256 amount;              // Amount to transfer
    uint256 destinationChain;    // Target chain ID
    address destinationAddress;  // Recipient on destination chain
    bytes extraData;             // Additional operation data
    uint256 nonce;               // Anti-replay nonce
    uint256 deadline;            // Intent expiration timestamp
}
```

#### Deposit State Tracking
```solidity
struct DepositState {
    address owner;               // Deposit owner
    address token;               // Token address
    uint256 amount;              // Deposit amount
    uint8 status;                // Current status (0-3)
    Intent intent;               // Associated intent
    uint256 timestamp;           // Deposit timestamp
    bytes32 commitmentHash;      // Commitment hash
}

enum IntentStatus {
    Pending,    // 0: Intent committed, awaiting deposit
    Proven,     // 1: Deposit proven, ready for execution
    Executed,   // 2: Successfully executed
    Failed      // 3: Failed or expired
}
```

#### Execution Calls
```solidity
struct Call {
    address target;    // Contract to call
    bytes data;        // Call data
    uint256 value;     // ETH value to send
}
```

### EIP-712 Implementation

#### Domain Separator
```solidity
bytes32 public constant DOMAIN_TYPEHASH = keccak256(
    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
);

bytes32 public constant TRAILS_INTENT_TYPEHASH = keccak256(
    "TrailsIntent(address sender,address token,uint256 amount,uint256 destinationChain,address destinationAddress,bytes extraData,uint256 nonce,uint256 deadline)"
);
```

#### Intent Hashing
```solidity
function hashIntent(Intent memory intent) public view returns (bytes32) {
    bytes32 structHash = keccak256(abi.encode(
        TRAILS_INTENT_TYPEHASH,
        intent.sender,
        intent.token,
        intent.amount,
        intent.destinationChain,
        intent.destinationAddress,
        keccak256(intent.extraData),
        intent.nonce,
        intent.deadline
    ));
    return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
}
```

## Core Functions

### Intent Commitment

#### `commitIntent(bytes32 transferId, Intent memory intent) external returns (bytes32)`
**IMPORTANT: This function is intended for relayers/operators, NOT end users.**

Commits an intent based on a user's existing transfer. Relayers detect user transfers via `TransferReceived` events and call this to validate and commit the associated intent.

**Parameters:**
- `transferId`: The ID of the user's pending transfer
- `intent`: Intent structure that should match the transfer details

**Returns:**
- `bytes32`: The computed intent hash

**Validation:**
- Transfer must exist and not be committed yet
- Intent sender must match transfer sender  
- Intent token/amount must match transfer token/amount
- Nonce must match sender's current nonce
- Transfer must not be expired

**Events:**
- `IntentCommitted(bytes32 indexed intentHash, bytes32 indexed transferId, address indexed sender, Intent intent)`

**Usage Context:**
Relayers monitor `TransferReceived` events from user transfers and validate the intent data before committing.

### Deposit Functions

#### ETH Deposits via Fallback
```solidity
fallback() external payable nonReentrant notPaused
```

**Mechanism:**
1. Extracts intent hash from last 32 bytes of calldata
2. Validates deposit matches committed intent
3. Emits deposit received event

**Usage:**
```javascript
// Send ETH with intent hash suffix
const calldata = ethers.utils.concat([
    "0x1234", // arbitrary data
    intentHash // 32-byte intent hash
]);

await wallet.sendTransaction({
    to: entrypoint.address,
    value: ethers.utils.parseEther("1.0"),
    data: calldata
});
```

#### ERC20 Deposits
```solidity
function depositERC20WithIntent(
    bytes32 intentHash,
    address token,
    uint256 amount
) external nonReentrant notPaused validIntentHash(intentHash)
```

**Parameters:**
- `intentHash`: The committed intent hash
- `token`: ERC20 token address
- `amount`: Amount to deposit

### Proof Functions

#### ETH Deposit Proof
```solidity
function proveETHDeposit(
    bytes32 intentHash,
    bytes calldata signature
) external nonReentrant notPaused validIntentHash(intentHash)
```

**Validation Process:**
1. Decodes signature using TrailsSignatureDecoder
2. Validates on-chain transaction proof via TrailsTxValidator
3. Updates status to Proven

#### ERC20 Deposit Proof
```solidity
function proveERC20Deposit(
    bytes32 intentHash,
    bytes calldata signature
) external nonReentrant notPaused validIntentHash(intentHash)
```

**Supported Signature Types:**
- On-chain transaction validation
- ERC20 permit signatures

### Execution Function

#### Generic Intent Execution
```solidity
function executeIntent(
    bytes32 intentHash,
    Call[] calldata calls
) external nonReentrant notPaused validIntentHash(intentHash)
```

**Execution Flow:**
1. Validates intent is in Proven status
2. Executes all calls in sequence
3. Handles success/failure scenarios
4. Automatic refund on failure

**Call Examples:**
```solidity
// Bridge operation
Call memory bridgeCall = Call({
    target: BRIDGE_CONTRACT,
    data: abi.encodeCall(IBridge.bridge, (token, amount, destChain)),
    value: 0
});

// Swap operation
Call memory swapCall = Call({
    target: DEX_CONTRACT,
    data: abi.encodeCall(IDEX.swap, (tokenIn, tokenOut, amountIn)),
    value: 0
});
```

### Emergency Functions

#### Emergency Withdrawal
```solidity
function emergencyWithdraw(bytes32 intentHash) external validIntentHash(intentHash)
```

**Conditions:**
- Only deposit owner can withdraw
- Intent must be Failed status OR expired

#### Intent Expiration
```solidity
function expireIntent(bytes32 intentHash) external validIntentHash(intentHash)
```

**Conditions:**
- Current timestamp > intent deadline
- Intent not already executed

## Usage Flows

### Standard Flow: ETH Bridge (User Transfer First)

```mermaid
sequenceDiagram
    participant User
    participant Frontend
    participant Entrypoint
    participant Relayer
    participant Bridge

    User->>Frontend: Express intent to bridge ETH
    Frontend->>User: Request ETH transfer with intent data
    User->>Entrypoint: fallback(intentData) + ETH [ONLY USER ACTION]
    Entrypoint-->>Relayer: TransferReceived event
    
    Note over Relayer: Detects transfer, validates intent
    Relayer->>Entrypoint: commitIntent(transferId, intent)
    Entrypoint-->>Relayer: IntentCommitted event
    
    Relayer->>Entrypoint: proveETHDeposit(intentHash, signature)
    Entrypoint-->>Relayer: IntentProven event
    
    Relayer->>Entrypoint: executeIntent(intentHash, [bridgeCall])
    Entrypoint->>Bridge: bridge(token, amount, destChain)
    Bridge-->>Entrypoint: success
    Entrypoint-->>Relayer: IntentExecuted event
```

### Advanced Flow: ERC20 Swap + Bridge (User Transfer First)

```mermaid
sequenceDiagram
    participant User
    participant Frontend
    participant Entrypoint
    participant Relayer
    participant DEX
    participant Bridge

    User->>Frontend: Express intent to swap + bridge ERC20
    Frontend->>User: Request ERC20 transfer with intent data
    User->>Entrypoint: depositERC20WithIntent(token, amount, intentData) [ONLY USER ACTION]
    Entrypoint-->>Relayer: TransferReceived event
    
    Note over Relayer: Detects transfer, validates intent
    Relayer->>Entrypoint: commitIntent(transferId, erc20Intent)
    Entrypoint-->>Relayer: IntentCommitted event
    
    Relayer->>Entrypoint: proveERC20Deposit(intentHash, permitSig)
    Entrypoint-->>Relayer: IntentProven event
    
    Relayer->>Entrypoint: executeIntent(intentHash, [swapCall, bridgeCall])
    Entrypoint->>DEX: swap(tokenA, tokenB, amount)
    Entrypoint->>Bridge: bridge(tokenB, swappedAmount, destChain)
    Entrypoint-->>Relayer: IntentExecuted event
```

## Security Considerations

### Access Control
- **Owner-only functions**: `setPaused`, `transferOwnership`
- **Deposit owner restrictions**: `emergencyWithdraw`
- **Public functions**: All others (with validation)

### Input Validation
- Zero address checks for critical parameters
- Amount validation (non-zero)
- Deadline validation (future timestamp, max 24 hours)
- Status validation for state transitions

### Reentrancy Protection
- Inherits from OpenZeppelin's `ReentrancyGuard`
- `nonReentrant` modifier on all state-changing functions

### Economic Security
- Intent expiration prevents indefinite fund locking
- Automatic refunds on execution failure
- Emergency withdrawal for failed intents

## Integration Guide

### Frontend Integration

#### 1. Intent Data Preparation
```javascript
// Frontend creates intent data to be included in transfer
const intent = {
    sender: userAddress,
    token: "0x0000000000000000000000000000000000000000", // ETH
    amount: ethers.utils.parseEther("1.0"),
    destinationChain: 137, // Polygon
    destinationAddress: userAddress,
    extraData: ethers.utils.hexlify(bridgeParams),
    nonce: await entrypoint.nonces(userAddress),
    deadline: Math.floor(Date.now() / 1000) + 3600 // 1 hour
};

// Encode intent data to include in transfer calldata
const intentData = ethers.utils.defaultAbiCoder.encode(
    ["tuple(address,address,uint256,uint256,address,bytes,uint256,uint256)"],
    [intent]
);
```

#### 2. User's 1-Click ETH Transfer (ONLY USER ACTION)
```javascript
// This is the ONLY action users need to take - truly 1-click!
// Transfer includes intent data in calldata
await user.sendTransaction({
    to: entrypoint.address,
    value: intent.amount,
    data: intentData // Intent data encoded above
});

// User is done! Relayer monitors TransferReceived events
// and handles everything else: commitment, proof, execution
```

#### 3. User's 1-Click ERC20 Transfer (ONLY USER ACTION)
```javascript
// This is the ONLY action users need to take - truly 1-click!
// Function signature changed to accept intent data directly
await entrypoint.depositERC20WithIntent(
    intent.token,
    intent.amount,
    intentData // Intent data encoded above
);

// User is done! Relayer monitors TransferReceived events
// and handles everything else: commitment, proof, execution
```

### Relayer/Backend Integration

#### 1. Transfer Monitoring (Relayer Responsibility)
```javascript
// Relayer monitors TransferReceived events from user transfers
entrypoint.on("TransferReceived", async (transferId, sender, token, amount, intentData) => {
    // Decode and validate intent data from user's transfer
    const [intent] = ethers.utils.defaultAbiCoder.decode(
        ["tuple(address,address,uint256,uint256,address,bytes,uint256,uint256)"],
        intentData
    );
    
    // Validate intent matches transfer
    if (intent.sender !== sender || intent.amount !== amount || intent.token !== token) {
        console.log("Invalid intent data, skipping");
        return;
    }
    
    // Commit the intent on behalf of user
    const intentHash = await entrypoint.commitIntent(transferId, intent);
    console.log("Intent committed:", intentHash);
});
```

#### 2. Intent Commitment (Relayer Responsibility)  
```javascript
// After monitoring transfers, relayer commits validated intents
entrypoint.on("IntentCommitted", async (intentHash, transferId, sender) => {
    // Generate proof for the user's transfer transaction
    const txProof = await generateTxProof(intentHash);
    
    // Prove the deposit based on the original transfer
    await entrypoint.proveETHDeposit(intentHash, txProof);
});
```

#### 3. Intent Execution (Relayer Responsibility)
```javascript
// Relayer prepares and executes the intent after proof
entrypoint.on("IntentProven", async (intentHash, prover) => {
    // Prepare execution calls
    const bridgeCalls = [{
        target: BRIDGE_CONTRACT,
        data: bridge.interface.encodeFunctionData("bridge", [
            intent.token,
            intent.amount,
            intent.destinationChain,
            intent.destinationAddress
        ]),
        value: intent.token === ethers.constants.AddressZero ? intent.amount : 0
    }];
    
    // Relayer executes the intent
    await entrypoint.executeIntent(intentHash, bridgeCalls);
});
```

## Gas Optimization

### Efficient Data Packing
- Uses `uint8` for status (vs `uint256`)
- Packs struct fields optimally
- Minimal storage writes

### Batch Operations
- Single transaction execution for multiple calls
- Reduces overall gas costs for complex operations

### Event Optimization
- Indexed parameters for efficient filtering
- Minimal event data to reduce gas

## Testing Strategy

### Unit Tests Coverage
- Intent commitment and validation
- Deposit flows (ETH and ERC20)
- Proof validation mechanisms
- Execution success and failure scenarios
- Emergency functions and admin operations
- Edge cases and error conditions

### Integration Tests
- End-to-end bridge operations
- Multi-step DeFi operations (swap + bridge)
- Cross-chain intent validation
- Failure recovery mechanisms

### Security Tests
- Reentrancy attack prevention
- Access control validation
- Input sanitization
- Economic attack scenarios

## Deployment Configuration

### Constructor Parameters
```solidity
constructor() {
    // Initialize EIP-712 domain separator
    DOMAIN_SEPARATOR = keccak256(abi.encode(
        DOMAIN_TYPEHASH,
        keccak256(bytes("TrailsEntrypointV2")),
        keccak256(bytes("1")),
        block.chainid,
        address(this)
    ));
    
    owner = msg.sender;
    paused = false;
}
```

### Required Dependencies
- OpenZeppelin contracts (ReentrancyGuard, SafeERC20, etc.)
- TrailsSignatureDecoder library
- TrailsTxValidator library  
- TrailsPermitValidator library
- RLPReader library

### Network-Specific Considerations
- Chain ID validation for intent hashing
- Gas price optimization for execution
- Block confirmation requirements for proof validation

## Future Enhancements

### Planned Features
1. **Batch Intent Commitment**: Multiple intents in single transaction
2. **Intent Cancellation**: User-initiated intent cancellation
3. **Delegated Execution**: Third-party execution with incentives
4. **Cross-Chain Intent Verification**: Validate intents across chains
5. **MEV Protection**: Front-running protection mechanisms

### Upgrade Path
- Implement proxy pattern for upgradability
- Maintain backward compatibility for existing intents
- Migration tools for transitioning between versions

## Conclusion

TrailsEntrypointV2 represents a revolutionary advancement in user experience for cross-chain and DeFi operations. By implementing a relayer-operated architecture where users only make transfers and third-party operators handle all intent management, it achieves true 1-click crypto transactions without any user-facing complexity.

**Key Achievements:**
- **True 1-Click Experience**: Users make only ONE action - a transfer with intent data
- **No Approvals**: Eliminates the traditional approve + transfer pattern
- **No Intent Management**: Users don't interact with commitments, proofs, or executions
- **Relayer-Operated**: Third parties handle all complexity on users' behalf
- **Security Maintained**: Full validation and proof requirements preserved

The contract's innovative combination of transfer suffixes, relayer operations, and commitment-proof patterns creates a new paradigm for truly user-friendly blockchain interactions, making complex multi-step operations as simple as sending a single transaction. This represents the next evolution in blockchain UX - from multi-step processes to genuine 1-click interactions.