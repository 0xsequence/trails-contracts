# Trails Contracts Documentation

Welcome to the comprehensive documentation for the Trails smart contract ecosystem.

## 📚 Documentation Index

### Core Contracts

#### 🚀 TrailsEntrypointV2 - Revolutionary 1-Click Transactions
**[Technical Specification →](TrailsEntrypointV2.md)**

The latest innovation in the Trails ecosystem: a single entrypoint contract that enables true 1-click crypto transactions by accepting intents through ETH/ERC20 transfers with calldata suffixes.

**Key Features:**
- Single entrypoint for all intent-based operations
- Transfer suffix pattern eliminates approve step
- Commit-prove pattern with signature validation
- Generic multicall execution for bridges, swaps, and DeFi operations
- Comprehensive safety mechanisms and emergency functions

#### 🔐 Sapient Signer Architecture
**[Sapient Signer Documentation →](SAPIENT_SIGNER.md)**

Framework for Sequence v3 wallet integration enabling off-chain attestation validation for automated protocol operations.

**Core Modules:**
- TrailsLiFiSapientSigner - LiFi protocol validation
- TrailsRelaySapientSigner - Relay operation validation  
- TrailsTokenSweeper - Token recovery utilities

## 🏗️ Architecture Overview

### Design Principles

1. **Intent-Based Operations**: All operations structured as EIP-712 intents
2. **Off-Chain Validation**: Signature-based proof validation
3. **Generic Execution**: Flexible multicall support for any protocol
4. **Safety First**: Comprehensive error handling and recovery mechanisms
5. **Gas Optimization**: Efficient data packing and minimal storage writes

### Integration Patterns

#### Frontend Integration
- Intent creation and commitment
- Transfer suffix pattern implementation
- Event monitoring and status tracking

#### Backend Integration  
- Transaction proof generation
- Signature validation and proving
- Intent execution orchestration

#### Cross-Chain Operations
- Bridge operation support
- Multi-hop transaction coordination
- Destination chain validation

## 🔧 Development Guide

### Quick Start

```bash
# Install dependencies
make install

# Build contracts
forge build

# Run tests
forge test

# Run specific tests
forge test --match-contract TrailsEntrypointV2Test
```

### Testing Strategy

Each contract includes comprehensive test coverage:

- **Unit Tests**: Individual function validation
- **Integration Tests**: End-to-end operation flows
- **Security Tests**: Attack prevention validation
- **Gas Optimization Tests**: Efficiency verification

### Deployment

Contracts use singleton deployment via ERC2470 for deterministic addresses across chains.

```bash
# Deploy with environment variables
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

## 🛡️ Security Considerations

### Access Control
- Owner-only administrative functions
- Deposit owner restrictions for withdrawals
- Public validation with comprehensive checks

### Economic Security
- Intent expiration prevents indefinite locking
- Automatic refunds on execution failure
- Emergency withdrawal mechanisms

### Technical Security
- Reentrancy protection via OpenZeppelin
- Comprehensive input validation
- Signature replay protection

## 🚀 Usage Examples

### Simple ETH Bridge

```javascript
// 1. Commit intent
const intent = {
    sender: userAddress,
    token: ZERO_ADDRESS, // ETH
    amount: parseEther("1.0"),
    destinationChain: 137, // Polygon
    destinationAddress: userAddress,
    extraData: "0x",
    nonce: await entrypoint.nonces(userAddress),
    deadline: Math.floor(Date.now() / 1000) + 3600
};

const intentHash = await entrypoint.commitIntent(intent);

// 2. Send ETH with intent hash suffix
const calldata = ethers.utils.concat([
    ethers.utils.randomBytes(32),
    intentHash
]);

await user.sendTransaction({
    to: entrypoint.address,
    value: intent.amount,
    data: calldata
});

// 3. Backend proves and executes
await entrypoint.proveETHDeposit(intentHash, txProof);
await entrypoint.executeIntent(intentHash, bridgeCalls);
```

### ERC20 Swap + Bridge

```javascript
// 1. Commit ERC20 intent
const intent = {
    sender: userAddress,
    token: USDC_ADDRESS,
    amount: parseUnits("100", 6),
    destinationChain: 42161, // Arbitrum
    destinationAddress: userAddress,
    extraData: encodeSwapData(USDC_ADDRESS, WETH_ADDRESS),
    nonce: await entrypoint.nonces(userAddress),
    deadline: Math.floor(Date.now() / 1000) + 3600
};

// 2. Deposit ERC20
await usdc.approve(entrypoint.address, intent.amount);
await entrypoint.depositERC20WithIntent(intentHash, USDC_ADDRESS, intent.amount);

// 3. Execute swap + bridge
const calls = [
    { target: DEX_ADDRESS, data: swapCalldata, value: 0 },
    { target: BRIDGE_ADDRESS, data: bridgeCalldata, value: 0 }
];

await entrypoint.executeIntent(intentHash, calls);
```

## 📈 Future Roadmap

### Planned Enhancements

1. **Batch Operations**: Multiple intents in single transaction
2. **Intent Cancellation**: User-initiated cancellation
3. **Delegated Execution**: Third-party execution incentives
4. **Cross-Chain Validation**: Multi-chain intent verification
5. **MEV Protection**: Front-running protection mechanisms

### Upgrade Strategy

- Proxy pattern implementation for upgradability
- Backward compatibility maintenance
- Migration tooling for version transitions

## 🤝 Contributing

### Development Workflow

1. Fork the repository
2. Create feature branch
3. Implement changes with tests
4. Run full test suite
5. Submit pull request with documentation

### Code Standards

- Solidity style guide compliance
- Comprehensive test coverage (>95%)
- Gas optimization awareness
- Security best practices
- Clear documentation

## 📞 Support & Community

For questions, discussions, or support:

- GitHub Issues for bug reports
- GitHub Discussions for feature requests
- Discord community for real-time chat

---

*Built with ❤️ by the Sequence team for the future of seamless cross-chain interactions.*