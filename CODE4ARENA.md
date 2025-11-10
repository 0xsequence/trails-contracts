# Trails Contracts — Code4rena Audit Prep

These contracts are used with **Trails** (https://docs.trails.build/) and Sequence v3 **sapient signer** wallets. The closed‑source **Intent Machine** is **out of scope** for this audit, but auditors can exercise public API interfaces that drive the on‑chain flows.

---

## 1) Areas of concern (attack surfaces & where to focus)

### A. Delegatecall‑only router pattern
- **Delegatecall enforcement & assumptions.** `TrailsRouter` / `TrailsRouterShim` are designed to be invoked **only via `delegatecall`** from Sequence v3 wallets; direct calls are blocked (e.g., `onlyDelegatecall`). Probe for any call paths that bypass this constraint, or any place wallet‑context assumptions (storage layout, `msg.sender`) can be violated by unintended delegatecalls.  
- **Storage sentinels & `opHash` gating.** Success/failure is tracked via a per‑op storage sentinel keyed by `opHash`; mistakes in setting/clearing, hash collisions, or re‑use could gate fee sweeps incorrectly. Validate namespacing and slot computation (e.g., `TrailsSentinelLib.successSlot(opHash)`), including Cancun tstore vs. sstore fallbacks.  
- **Multicall3 behavior.** The router composes approvals, swaps, bridges via `IMulticall3.aggregate3Value`. Stress revert bubbling, partial‑success semantics (when upstream sets `behaviorOnError = IGNORE`), and ensure approvals can’t be stranded in a half‑updated state.

### B. Balance injection & calldata surgery
- **`injectAndCall` / `injectSweepAndCall`.** Calldata manipulation uses a fixed 32‑byte placeholder and a provided `amountOffset`. Focus on: offset correctness, alignment, endianness, fee‑on‑transfer tokens, and ETH vs ERC‑20 branches (value forwarding vs approval path). Look for out‑of‑bounds writes and incorrect placeholder detection.  
- **Approval handling quirks.** Uses `SafeERC20.forceApprove` (for USDT‑like tokens). Validate no approval race or leftover unlimited approvals after failure paths.

### C. Fee collection & refund semantics
- **Conditional fee sweeps.** `validateOpHashAndSweep(opHash, token, feeCollector)` should only fire when the success sentinel was set by the shim; verify there’s no path to set the sentinel on partial/incorrect success. Ensure `refundAndSweep` cannot under‑refund the user or over‑sweep to fees when origin calls fail.  
- **Destination failures.** When destination protocol calls fail, the intended behavior is to sweep funds to the user *on the destination chain* (no “undo bridge”). Validate this always occurs and can’t be front‑run/griefed into a stuck state.

### D. Entrypoint contracts (two surfaces)
- **`TrailsIntentEntrypoint` (EIP‑712 deposits + optional permits).** Review replay protection, deadline checks, nonces, and the “leftover allowance → `payFee` / `payFeeWithPermit`” pattern so fee collection can’t exceed expectations or happen without user intent. Check reentrancy guard coverage.  
- **`TrailsEntrypointV2` (“transfer‑first”, commit‑prove‑execute).** UX hinges on: (1) extracting the intent hash from the last 32 bytes of calldata on ETH deposits, (2) validating proof/commitment linkage, (3) correct status transitions (`Pending` → `Proven` → `Executed/Failed`). Audit proof validators and signature decoding, expiry logic, and emergency withdrawal gating.

### E. Sapient Signer modules (wallet‑side attestation)
- **Target pinning & `imageHash` matching.** For LiFi, calls must target the immutable `TARGET_LIFI_DIAMOND` and the attestation‑derived `lifiIntentHash` must match the leaf’s `imageHash`. Validate decoding and signer recovery over `payload.hashFor(address(0))`. Any bypass → arbitrary call authorization.

### F. Cross‑chain assumptions
- **Non‑atomicity & monitoring.** Origin/destination legs are decoupled by bridges/relayers. Stress timing windows, reorgs around proofing, dust handling, token decimal mismatches, and MEV on destination protocol interactions (especially with balance injection).

---

## 2) Main invariants (what must always hold true)

**Router/Shim invariants**
- Router/RouterShim functions **execute only via `delegatecall`** from a Sequence v3 wallet context. Any direct call must revert via `onlyDelegatecall`.  
- A fee sweep using `validateOpHashAndSweep(opHash, …)` **must** observe `SUCCESS_VALUE` at the sentinel slot computed for that `opHash`; otherwise it reverts and **no fees are taken**.  
- Fallback refund path `refundAndSweep` **only** runs when the immediately previous step reverted under `behaviorOnError = IGNORE` (“onlyFallback” semantics). On success paths, fallback calls are skipped.  
- Balance injection (`injectAndCall`) **must** replace exactly the placeholder bytes at `amountOffset` and use the *current* wallet balance/allowance at call time (ETH via `value`, ERC‑20 via `forceApprove`)—never a guessed amount.

**State/sentinels invariants**
- The success sentinel slot is **namespaced** (no collisions with wallet storage) and keyed by `opHash`; it is set **only** after `RouterShim`’s wrapped call completes successfully.

**Economic invariants**
- On **origin failure**, the user is refunded on origin (funds never bridged), and fees—if collected—come only from remaining balances after refund logic (no user loss beyond quoted fees).  
- On **destination failure**, the user receives tokens on the destination chain via a sweep; no hidden fee collection occurs there beyond the defined sweep step.

**`TrailsIntentEntrypoint` invariants**
- Deposits (`depositToIntent` / `…WithPermit`) **must** match signed EIP‑712 intent (user, token, amount, intentAddress, deadline), with replay blocked by tracked intent hashes and deadline enforced. Reentrancy is guarded.  
- Fee payments (`payFee`, `payFeeWithPermit`) can only move `feeAmount` from the user to `feeCollector` when there is sufficient allowance **or** a valid ERC‑2612 permit for that exact amount by the deadline.

**`TrailsEntrypointV2` invariants**
- **ETH deposits** pull the intent hash from the last 32 bytes of calldata; the committed intent must match sender/token/amount/nonce and be within deadline before proofing. Status transitions are linear: `Pending → Proven → Executed/Failed`. Emergency withdraw is restricted to the deposit owner in Failed/expired states. All state changers are `nonReentrant`.

**Sapient Signer (wallet) invariants**
- For LiFi operations, **every call target** must equal the immutable `TARGET_LIFI_DIAMOND`; recovered attestation signer + decoded LiFi data must hash to the leaf’s `imageHash` for weight to count. Any mismatch rejects the signature.

---

## 3) Trusted roles

> Protocol is **not** fully permissionless. These are the explicit trust/authority points for the in‑scope contracts.

| Role | Surface | Authority / Notes |
|---|---|---|
| **Owner** | `TrailsEntrypointV2` | Admin actions incl. `pause`/`unpause` and ownership transfer; emergency/expiry rules enforced at function level. Public flows otherwise permissionless with validation. |
| **Deposit owner (user)** | `TrailsEntrypointV2` | Can `emergencyWithdraw(intentHash)` only when status is Failed or expired; cannot override happy‑path execution. |
| **Relayers / operators** | `TrailsEntrypointV2` | Call `commitIntent`, `prove*Deposit`, `executeIntent`. Unprivileged (validations gate success) but control **liveness/censorship** by choosing to act or not. |
| **Sapient signer keys** | Wallet side | Off‑chain keys that produce attestations. Trust is in correct wallet configuration (`imageHash`) and key custody; module pins LiFi diamond target. |

*(`TrailsRouter` / `TrailsRouterShim` execute under Sequence v3 wallet authority via `delegatecall`; there’s no standalone admin role on these stateless extensions.)*

---

## 4) Build from fresh clone & run tests

```bash
forge install
forge build
forge test
```

---

## Scope notes for Code4rena
- **In‑scope contracts:** `TrailsRouter`, `TrailsRouterShim`, `TrailsIntentEntrypoint`, `TrailsEntrypointV2`, and their libraries. Auditors can interact via the same public API patterns documented (multicall, sweep, injection, EIP‑712 deposit/permit, transfer‑suffix path).  
- **Out of scope:** The closed‑source **Intent Machine** (backend), while auditors can still hit the **public API interfaces** and simulate the flows described in the flow docs.  
- **Context coupling:** These contracts are meant to operate with **Sequence v3 Sapient Signer wallets** (delegatecall extensions; attestation‑based validation); reviewers should model threats with that in mind.
