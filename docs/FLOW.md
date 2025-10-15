# Trails Contracts - Technical Flow Diagrams

Technical sequence diagrams documenting Trails contract interactions.

---

## 1. Cross-Chain Flow WITHOUT Destination Calldata

**Core Gist:** User bridges/swaps tokens across chains with no custom action on destination

**Key Characteristics:**
- Chains differ between origin and destination
- No protocol interaction on destination (just a simple transfer)
- User receives bridged tokens directly

**Scenario Specifics:** Arbitrum USDC → Base USDC (simple receive/pay/fund scenarios)

### Call Batch Sequence (Origin Chain):
1. **Call #1:** Origin swap and bridge via TrailsRouterShim
2. **Call #2:** Fee collection via `validateOpHashAndSweep()` (success path)
3. **Call #3:** Refund and fee collection via `refundAndSweep()` (fallback path, only if Call #1 fails)

### Call Batch Sequence (Destination Chain):
1. **Call #1:** Sweep tokens to user via `sweep()`

```mermaid
sequenceDiagram
    participant User as User EOA
    participant OriginIntent as Origin Intent Address<br/>(Sequence v3 Wallet)
    participant Shim as TrailsRouterShim
    participant Router as TrailsRouter
    participant MC3 as Multicall3<br/>(0xcA11...bde05)
    participant Bridge as Bridge Protocol<br/>(LiFi/Relay)
    participant DestIntent as Destination Intent Address<br/>(Sequence v3 Wallet)
    participant FeeCollector as Fee Collector

    Note over User,FeeCollector: ORIGIN CHAIN EXECUTION

    User->>OriginIntent: Transfer tokens/ETH<br/>(initial deposit)

    Note over OriginIntent: Relayer detects deposit<br/>Initiates execution

    rect rgb(240, 248, 255)
        Note over OriginIntent,MC3: CALL #1 - Origin Swap & Bridge
        OriginIntent->>Shim: (delegatecall)<br/>handleSequenceDelegateCall(opHash, data)
        Note over Shim: Decode: (bytes inner, uint256 callValue)<br/>Validate: selector == 0x174dea71 (aggregate3Value)
        Shim->>Router: (call with value)<br/>pullAndExecute(token, multicall3Data)
        Router->>MC3: (delegatecall)<br/>aggregate3Value(calls[])
        Note over MC3: Execute batch:<br/>1. Token approvals<br/>2. DEX swap<br/>3. Bridge protocol call
        MC3->>Bridge: Bridge tokens to destination
        MC3-->>Router: success
        Router-->>Shim: returnData
        Note over Shim: _setTstorish(successSlot(opHash), SUCCESS_VALUE)
        Shim-->>OriginIntent: return
    end

    rect rgb(240, 255, 240)
        Note over OriginIntent,FeeCollector: CALL #2 - Fee Collection (Success Path)
        OriginIntent->>Router: (delegatecall)<br/>handleSequenceDelegateCall(opHash, validateOpHashAndSweep data)
        Note over Router: Validate: _getTstorish(slot) == SUCCESS_VALUE
        Router->>Router: sweep(token, feeCollector)
        Router->>FeeCollector: Transfer remaining balance (fees)
        Router-->>OriginIntent: return
    end

    Note over User,FeeCollector: DESTINATION CHAIN EXECUTION

    Note over DestIntent: Relayer detects bridged funds

    rect rgb(255, 250, 240)
        Note over DestIntent,User: DEST CALL #1 - Sweep to User
        DestIntent->>Router: (delegatecall)<br/>handleSequenceDelegateCall(opHash, sweep data)
        Router->>Router: sweep(token, user)
        Router->>User: Transfer all tokens
        Router-->>DestIntent: return
    end
```

### Implementation Notes:

- **Sentinel lifetime:** Uses `Tstorish` library (tstore on Cancun+, falls back to sstore on older chains)
- **Fee structure:** Fees are taken on the origin chain from whatever's left after bridging
- **Why TrailsRouterShim exists:** Quote providers need a fixed "from" address, but we need the quote to construct the address. TrailsRouterShim needed to overcome this circular dependency.

---

## 2. Cross-Chain Flow WITH Destination Calldata (Balance Injection)

**Core Gist:** User bridges tokens + executes custom protocol interaction on destination with exact bridged amount

**Key Characteristics:**
- Cross-chain flow with destination protocol interaction
- Common use cases: DeFi deposits (Aave, Morpho), NFT minting
- Bridge amount is unknown beforehand (slippage and fees vary)
- Runtime balance injection via `injectAndCall()` fills in the actual amount
- Backend calculates `amountOffset` where placeholder lives in the calldata

**Scenario Specifics:** Arbitrum USDC → Base USDC + Aave deposit | Base ETH → Arbitrum ETH + NFT mint

### Call Batch Sequence (Origin Chain):
1. **Call #1:** Origin swap and bridge via TrailsRouterShim
2. **Call #2:** Fee collection via `validateOpHashAndSweep()` (success path)
3. **Call #3:** Refund and fee collection via `refundAndSweep()` (fallback path, only if Call #1 fails)

### Call Batch Sequence (Destination Chain):
1. **Call #1:** Inject balance and execute protocol interaction via `injectAndCall()`
2. **Call #2:** Sweep tokens to user via `sweep()` (fallback if Call #1 fails)

```mermaid
sequenceDiagram
    participant User as User EOA
    participant OriginIntent as Origin Intent Address<br/>(Sequence v3 Wallet)
    participant Shim as TrailsRouterShim
    participant Router as TrailsRouter
    participant MC3 as Multicall3
    participant Bridge as Bridge Protocol<br/>(LiFi/Relay)
    participant DestIntent as Destination Intent Address<br/>(Sequence v3 Wallet)
    participant Protocol as Destination Protocol<br/>(Aave/Morpho/NFT)
    participant FeeCollector as Fee Collector

    Note over User,FeeCollector: ORIGIN CHAIN EXECUTION (Same as Flow #1)

    User->>OriginIntent: Transfer tokens/ETH

    rect rgb(240, 248, 255)
        Note over OriginIntent,MC3: CALL #1 - Origin Swap & Bridge
        OriginIntent->>Shim: (delegatecall)<br/>handleSequenceDelegateCall(opHash, data)
        Shim->>Router: (call with value)<br/>pullAndExecute(token, multicall3Data)
        Router->>MC3: (delegatecall) aggregate3Value(calls[])
        MC3->>Bridge: Bridge tokens to destination
        MC3-->>Router: success
        Router-->>Shim: returnData
        Note over Shim: _setTstorish(successSlot(opHash), SUCCESS_VALUE)
        Shim-->>OriginIntent: return
    end

    rect rgb(240, 255, 240)
        Note over OriginIntent,FeeCollector: CALL #2 - Fee Collection (Success Path)
        OriginIntent->>Router: (delegatecall) validateOpHashAndSweep
        Router->>FeeCollector: Transfer remaining balance (fees)
        Router-->>OriginIntent: return
    end

    Note over User,FeeCollector: DESTINATION CHAIN EXECUTION

    Note over DestIntent: Relayer detects bridged funds

    rect rgb(255, 250, 240)
        Note over DestIntent,Protocol: DEST CALL #1 - Inject Balance & Execute Protocol
        DestIntent->>Router: (delegatecall)<br/>handleSequenceDelegateCall(opHash, injectAndCall data)
        Note over Router: Decode params:<br/>(token, target, callData, amountOffset, placeholder)
        Note over Router: Read actual balance:<br/>callerBalance = _getSelfBalance(token)
        Note over Router: Find placeholder (0xdeadbeef...deadbeef)<br/>at amountOffset in callData
        Note over Router: Replace placeholder with callerBalance
        alt Native ETH (token == address(0))
            Router->>Protocol: (call with value=callerBalance)<br/>injectedCallData
        else ERC20 Token
            Router->>Router: SafeERC20.forceApprove(token, target, callerBalance)
            Router->>Protocol: (call)<br/>injectedCallData
        end
        Protocol-->>Router: success (deposit/mint completed)
        Router-->>DestIntent: return
    end

    Note over DestIntent: If protocol call succeeds,<br/>flow ends here

    rect rgb(255, 240, 240)
        Note over DestIntent,User: DEST CALL #2 - Sweep to User (Fallback)
        Note over DestIntent: If Call #1 reverts:
        DestIntent->>Router: (delegatecall)<br/>handleSequenceDelegateCall(opHash, sweep data)
        Note over Router: onlyFallback=false<br/>(part of main path)
        Router->>Router: sweep(token, user)
        Router->>User: Transfer all remaining tokens<br/>(on destination chain)
        Router-->>DestIntent: return
    end
```

### Implementation Notes:

- **Why injection?** The bridge amount isn't known until funds actually arrive (slippage and fees affect the final amount)
- **Placeholder format:** We use `0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef` as a 32-byte marker
- **amountOffset:** Backend figures out where in the calldata the placeholder sits (byte offset)
- **Native ETH:** No injection needed (amountOffset=0, placeholder=0). We just forward msg.value
- **ERC20 approvals:** `SafeERC20.forceApprove` handles quirky tokens like USDT that need zero approval first
- **Refund location:** If the protocol call fails, user gets tokens on the destination chain, not origin
- **Refunds on destination chain:** Once bridged, the refunds are handled automatically on the destination chain w/ destination token

---

## 3. Same-Chain Flow WITHOUT Destination Calldata

**Core Gist:** User swaps tokens on same chain with no additional protocol interaction

**Key Characteristics:**
- Everything happens on one chain
- Just a DEX swap, no bridging
- No protocol interaction beyond the swap itself
- Atomic—entire flow is one transaction
- Fees get collected before user receives swapped tokens

**Scenario Specifics:** Base USDC → Base ETH | Base ETH → Base USDC

### Call Batch Sequence (Same Chain):
1. **Call #1:** Swap via TrailsRouterShim
2. **Call #2:** Fee collection via `validateOpHashAndSweep()` (success path)
3. **Call #3:** Refund and fee collection via `refundAndSweep()` (fallback path, only if Call #1 fails)
4. **Call #4:** Sweep swapped tokens to user via `sweep()`

```mermaid
sequenceDiagram
    participant User as User EOA
    participant Intent as Intent Address<br/>(Sequence v3 Wallet)
    participant Shim as TrailsRouterShim
    participant Router as TrailsRouter
    participant MC3 as Multicall3
    participant DEX as DEX Protocol<br/>(Uniswap/etc)
    participant FeeCollector as Fee Collector

    Note over User,FeeCollector: SAME CHAIN EXECUTION (Atomic)

    User->>Intent: Transfer tokens/ETH<br/>(initial deposit)

    Note over Intent: Relayer detects deposit<br/>Initiates execution

    rect rgb(240, 248, 255)
        Note over Intent,DEX: CALL #1 - Token Swap
        Intent->>Shim: (delegatecall)<br/>handleSequenceDelegateCall(opHash, data)
        Note over Shim: Validate: selector == 0x174dea71
        Shim->>Router: (call with value)<br/>pullAndExecute(token, multicall3Data)
        Router->>MC3: (delegatecall)<br/>aggregate3Value(calls[])
        Note over MC3: Execute batch:<br/>1. Token approvals<br/>2. DEX swap (NO bridge)
        MC3->>DEX: Swap tokens
        DEX-->>MC3: Return swapped tokens
        MC3-->>Router: success
        Router-->>Shim: returnData
        Note over Shim: _setTstorish(successSlot(opHash), SUCCESS_VALUE)
        Shim-->>Intent: return
    end

    rect rgb(240, 255, 240)
        Note over Intent,FeeCollector: CALL #2 - Fee Collection (Success Path)
        Intent->>Router: (delegatecall)<br/>handleSequenceDelegateCall(opHash, validateOpHashAndSweep data)
        Note over Router: Validate: _getTstorish(slot) == SUCCESS_VALUE
        Router->>Router: sweep(token, feeCollector)
        Router->>FeeCollector: Transfer remaining balance (fees)
        Router-->>Intent: return
    end

    rect rgb(255, 250, 240)
        Note over Intent,User: CALL #4 - Sweep Swapped Tokens to User
        Intent->>Router: (delegatecall)<br/>handleSequenceDelegateCall(opHash, sweep data)
        Router->>Router: sweep(swappedToken, user)
        Router->>User: Transfer all swapped tokens
        Router-->>Intent: return
    end
```

### Implementation Notes:

- **Atomic:** Everything's in one transaction, no waiting around
- **Fee timing:** Collect fees before sending swapped tokens to the user
- **Simpler:** No balance injection—amounts doesn't exist

---

## 4. Same-Chain Flow WITH Destination Calldata (Direct Replacement)

**Core Gist:** User swaps tokens AND executes protocol interaction on same chain

**Key Characteristics:**
- Same-chain flow with protocol interaction
- Use cases: DeFi deposits, NFT minting on the same chain
- Amount is deterministic since there's no bridge uncertainty
- NO `injectAndCall()` wrapper—backend replaces placeholder before intent creation
- Optimization: skips TrailsRouter wrapper entirely
- Backend pre-calculates the post-swap amount (accounting for slippage)

**Scenario Specifics:** Base ETH → Base USDC + Aave deposit | Base ETH → Base USDC + Morpho deposit

### Call Batch Sequence (Same Chain):
1. **Call #1:** Swap via TrailsRouterShim
2. **Call #2:** Fee collection via `validateOpHashAndSweep()` (success path)
3. **Call #3:** Refund and fee collection via `refundAndSweep()` (fallback path, only if Call #1 fails)
4. **Call #4:** Execute protocol interaction with predetermined amount (direct call, no TrailsRouter wrapper)

```mermaid
sequenceDiagram
    participant Backend as Trails Backend
    participant User as User EOA
    participant Intent as Intent Address<br/>(Sequence v3 Wallet)
    participant Shim as TrailsRouterShim
    participant Router as TrailsRouter
    participant MC3 as Multicall3
    participant DEX as DEX Protocol
    participant Protocol as Destination Protocol<br/>(Aave/Morpho)
    participant FeeCollector as Fee Collector

    Note over Backend,Protocol: PREPROCESSING (Before Intent Creation)

    rect rgb(250, 250, 250)
        Note over Backend: Detection logic:<br/>originChainId === destinationChainId<br/>originToken === destinationToken
        Note over Backend: Calculate exact post-swap amount<br/>with slippage tolerance
        Note over Backend: Direct placeholder replacement:<br/>Replace 0xdeadbeef with actual amount<br/>BEFORE intent creation
        Note over Backend: NO TrailsRouter.injectAndCall wrapper
    end

    Note over User,FeeCollector: SAME CHAIN EXECUTION

    User->>Intent: Transfer tokens/ETH

    rect rgb(240, 248, 255)
        Note over Intent,DEX: CALL #1 - Token Swap
        Intent->>Shim: (delegatecall) handleSequenceDelegateCall
        Shim->>Router: (call with value) pullAndExecute
        Router->>MC3: (delegatecall) aggregate3Value
        MC3->>DEX: Swap tokens
        DEX-->>MC3: Return swapped tokens
        MC3-->>Router: success
        Router-->>Shim: returnData
        Note over Shim: _setTstorish(successSlot(opHash), SUCCESS_VALUE)
        Shim-->>Intent: return
    end

    rect rgb(240, 255, 240)
        Note over Intent,FeeCollector: CALL #2 - Fee Collection (Success Path)
        Intent->>Router: (delegatecall) validateOpHashAndSweep
        Router->>FeeCollector: Transfer fees
        Router-->>Intent: return
    end

    rect rgb(255, 250, 240)
        Note over Intent,Protocol: CALL #4 - Protocol Interaction (Direct)
        Intent->>Protocol: (call) Deposit/Mint with predetermined amount
        Note over Protocol: No TrailsRouter wrapper<br/>Direct protocol call
        Protocol-->>Intent: success
    end
```

### Implementation Notes:

- **vs. cross-chain:** Amount is knowable ahead of time (no bridge = no uncertainty)
- **Optimization:** We skip the `injectAndCall()` wrapper since the amount is predetermined
- **How we detect this case:** The `wrapCalldataWithTrailsRouterIfNeeded()` function checks if we're on the same chain:
  ```typescript
  if (originChainId === destinationChainId && isSameToken) {
    const calldataWithAmount = calldata.replace(placeholderHex, amountHex)
    return { encodedCalldata: calldataWithAmount, trailsRouterAddress: target }
  }
  ```
- **Direct execution:** Protocol receives calldata with the real amount baked in

---

## 5. Origin Chain Failure & Refund Flow

**Core Gist:** Swap/bridge operation fails on origin chain, user receives full refund

**Key Characteristics:**
- Swap/bridge call fails before any funds leave the origin chain
- Sentinel never gets set (the revert happens before `_setTstorish`)
- Fee collection call also fails since sentinel is missing
- Refund call kicks in via the onlyFallback mechanism
- User gets refunded on origin (funds never made it across)
- We still collect fees even though the operation failed

**Scenario Specifics:** Invalid quote provider, insufficient liquidity, DEX revert, bridge unavailable

### Call Batch Sequence (Origin Chain - Failure):
1. **Call #1:** Origin swap and bridge via TrailsRouterShim **FAILS** (sentinel NOT set)
2. **Call #2:** Fee collection via `validateOpHashAndSweep()` **FAILS** (sentinel not set, skipped)
3. **Call #3:** Refund and fee collection via `refundAndSweep()` **EXECUTES** (onlyFallback=true, errorFlag=true)

```mermaid
sequenceDiagram
    participant User as User EOA
    participant Intent as Origin Intent Address<br/>(Sequence v3 Wallet)
    participant Calls as Calls Module<br/>(Sequence v3)
    participant Shim as TrailsRouterShim
    participant Router as TrailsRouter
    participant MC3 as Multicall3
    participant FeeCollector as Fee Collector

    Note over User,FeeCollector: ORIGIN CHAIN EXECUTION - Failure Scenario

    User->>Intent: Transfer tokens/ETH<br/>(initial deposit)

    rect rgb(255, 240, 240)
        Note over Intent,MC3: CALL #1 - Origin Swap/Bridge FAILS
        Intent->>Shim: (delegatecall)<br/>handleSequenceDelegateCall(opHash, data)
        Note over Shim: Validate selector: 0x174dea71
        Shim->>Router: (call with value)<br/>pullAndExecute(token, multicall3Data)
        Router->>MC3: (delegatecall)<br/>aggregate3Value(calls[])
        Note over MC3: Execute batch:<br/>Token approvals → DEX swap/bridge
        MC3--xRouter: REVERT (swap fails, insufficient liquidity)
        Router--xShim: REVERT (bubbles up)
        Note over Shim: Sentinel NOT set<br/>(revert before _setTstorish)
        Shim--xIntent: REVERT
        Note over Calls: Catch revert<br/>(behaviorOnError = IGNORE)<br/>Set errorFlag = true
    end

    rect rgb(255, 230, 230)
        Note over Intent,Router: CALL #2 - Fee Collection FAILS (Sentinel Not Set)
        Intent->>Router: (delegatecall)<br/>handleSequenceDelegateCall(opHash, validateOpHashAndSweep data)
        Note over Router: Check: _getTstorish(slot) == SUCCESS_VALUE
        Note over Router: Sentinel NOT set → REVERT
        Router--xIntent: REVERT SuccessSentinelNotSet
        Note over Calls: errorFlag = true (already set)
    end

    rect rgb(240, 255, 240)
        Note over Intent,FeeCollector: CALL #3 - Refund & Fee Collection (Fallback)
        Note over Calls: onlyFallback=true condition met<br/>(errorFlag=true from Call #2 revert)
        Intent->>Router: (delegatecall)<br/>handleSequenceDelegateCall(opHash, refundAndSweep data)
        Note over Router: Decode params:<br/>(token, refundRecipient, refundAmount, sweepRecipient)

        alt Balance >= refundAmount
            Router->>User: Transfer refundAmount (original deposit)
        else Balance < refundAmount
            Note over Router: Emit ActualRefund event<br/>(actualRefund < refundAmount)
            Router->>User: Transfer actual balance
        end

        Note over Router: Calculate remaining = _getSelfBalance(token)
        Router->>FeeCollector: Transfer remaining balance (fees)
        Note over Router: Emit RefundAndSweep event
        Router-->>Intent: return
    end
```

### Implementation Notes:

- **errorFlag:** The Calls module sets this when a call reverts with `behaviorOnError = IGNORE`
- **onlyFallback logic:** These calls only run if the previous call reverted
- **Fees on failure:** Fees are collected on the origin chain from any remaining balance during the fallback refund path, even if the transaction fails.
- **Partial refunds:** If there's not enough balance for the full refund, we send what's there and emit `ActualRefund`
- **Atomicity:** Everything happens in one transaction—no way to double-spend

---

## 6. Destination Chain Failure & Refund Flow

**Core Gist:** Bridge succeeds but destination protocol interaction fails, user receives tokens on destination

**Key Characteristics:**
- Origin side works perfectly (swap, bridge, fees all good)
- Funds make it across to destination
- Protocol interaction fails on destination (Aave revert, NFT sold out, etc.)
- Sweep call executes to refund the user
- User gets tokens on destination chain, NOT back on origin
- There's no automatic "undo bridge" mechanism
- If user wants funds back on origin, they bridge manually

**Scenario Specifics:** Invalid calldata, protocol revert (Aave insufficient collateral, NFT sold out), target contract paused

### Call Batch Sequence (Origin Chain):
1. **Call #1:** Origin swap and bridge **SUCCEEDS**
2. **Call #2:** Fee collection **SUCCEEDS**

### Call Batch Sequence (Destination Chain - Failure):
1. **Call #1:** Inject balance and execute protocol via `injectAndCall()` **FAILS**
2. **Call #2:** Sweep tokens to user via `sweep()` **EXECUTES**

```mermaid
sequenceDiagram
    participant OriginChain as Origin Chain<br/>(Successful)
    participant DestIntent as Destination Intent Address<br/>(Sequence v3 Wallet)
    participant Router as TrailsRouter
    participant Protocol as Destination Protocol<br/>(Aave/Morpho/NFT)
    participant User as User EOA

    Note over OriginChain: Origin chain execution succeeded<br/>Tokens successfully bridged

    Note over DestIntent,User: DESTINATION CHAIN EXECUTION - Protocol Failure

    Note over DestIntent: Relayer detects bridged funds

    rect rgb(255, 240, 240)
        Note over DestIntent,Protocol: DEST CALL #1 - Protocol Interaction FAILS
        DestIntent->>Router: (delegatecall)<br/>handleSequenceDelegateCall(opHash, injectAndCall data)
        Note over Router: Decode params:<br/>(token, target, callData, amountOffset, placeholder)
        Note over Router: Read balance: _getSelfBalance(token)
        Note over Router: Validate placeholder at amountOffset
        Note over Router: Replace placeholder with actual balance

        alt Native ETH
            Router->>Protocol: (call with value)<br/>injectedCallData
        else ERC20
            Router->>Router: SafeERC20.forceApprove(token, target, balance)
            Router->>Protocol: (call) injectedCallData
        end

        Note over Protocol: Protocol execution fails:<br/>- Invalid calldata (0xdeadbeef)<br/>- Contract logic revert<br/>- Insufficient collateral<br/>- NFT sold out<br/>- Contract paused
        Protocol--xRouter: REVERT (protocol-specific error)
        Note over Router: Entire injectAndCall reverts
        Router--xDestIntent: REVERT TargetCallFailed(revertData)
    end

    rect rgb(240, 255, 240)
        Note over DestIntent,User: DEST CALL #2 - Sweep to User (Fallback)
        Note over DestIntent: Execute next call in payload
        DestIntent->>Router: (delegatecall)<br/>handleSequenceDelegateCall(opHash, sweep data)
        Note over Router: onlyFallback=false<br/>(part of normal call sequence)
        Router->>Router: sweep(token, user)
        Note over Router: Calculate balance = _getSelfBalance(token)
        Router->>User: Transfer all remaining tokens<br/>(TO DESTINATION CHAIN USER WALLET)
        Note over Router: Emit Sweep event
        Router-->>DestIntent: return
    end

    Note over User: User receives tokens on DESTINATION chain<br/>NOT on origin chain
```

---

## Summary: Call Batch Sequences by Flow Type

### Cross-Chain Flows (Success)
**Origin Chain:**
1. **Call #1:** Swap + Bridge via TrailsRouterShim → Sets sentinel on success
2. **Call #2:** `validateOpHashAndSweep()` → Collects fees (success path)
3. **Call #3:** `refundAndSweep()` → Skipped (onlyFallback, but no errorFlag)

**Destination Chain (WITHOUT calldata):**
1. **Call #1:** `sweep(user)` → Transfer all tokens to user

**Destination Chain (WITH calldata - injection):**
1. **Call #1:** `injectAndCall()` → Inject balance + execute protocol
2. **Call #2:** `sweep(user)` → Skipped if Call #1 succeeds

### Same-Chain Flows (Success)
1. **Call #1:** Swap via TrailsRouterShim → Sets sentinel on success
2. **Call #2:** `validateOpHashAndSweep()` → Collects fees (success path)
3. **Call #3:** `refundAndSweep()` → Skipped (onlyFallback, but no errorFlag)
4. **Call #4:** `sweep(user)` OR direct protocol call → Transfer tokens or execute protocol

### Origin Chain Failure
1. **Call #1:** Swap/Bridge via TrailsRouterShim → **FAILS** (sentinel NOT set)
2. **Call #2:** `validateOpHashAndSweep()` → **FAILS** (sentinel missing, errorFlag set)
3. **Call #3:** `refundAndSweep()` → **EXECUTES** (onlyFallback + errorFlag)

### Destination Chain Failure (After Successful Bridge)
**Origin Chain:** All calls succeed (1, 2 complete normally)

**Destination Chain:**
1. **Call #1:** `injectAndCall()` → **FAILS** (protocol revert)
2. **Call #2:** `sweep(user)` → **EXECUTES** (refund on destination chain)

---

## Summary Table: Flow Decision Matrix

| Scenario | Origin Chain | Destination Chain | Injection Used? | Key Function |
|----------|--------------|-------------------|-----------------|--------------|
| Cross-chain simple transfer | Same as any flow | `sweep(user)` | No | N/A |
| Cross-chain with dest calldata | Same as any flow | `injectAndCall()` | **Yes** | Balance unknown until post-bridge |
| Same-chain simple swap | `pullAndExecute()` | N/A (same chain) | No | N/A |
| Same-chain with dest calldata | `pullAndExecute()` | N/A (same chain) | **No** | Backend replaces placeholder pre-intent |
| Origin failure | `refundAndSweep()` (fallback) | N/A (never bridged) | No | Refund + fee collection |
| Destination failure | Same as any flow | `sweep(user)` (after revert) | Attempted but failed | Refund on destination chain |
