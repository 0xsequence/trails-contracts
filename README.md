# Trails Contracts

Smart contracts for [Sequence Trails](https://trails.build).

## Contracts

### TrailsUtils

All modules are combined into a single [TrailsUtils.sol](src/TrailsUtils.sol) to reduce gas costs.

### Modules

#### HydrateProxy

[HydrateProxy.sol](src/modules/HydrateProxy.sol) is used as a proxy for Calls that may need modification at runtime.

Some Payload Calls require parameter encoding that is only available during execution. For example, a Call may require the ERC20 balance to be encoded, but the exact value may change due to slippage. Payloads may also have the circular dependency issue where the Call must encode the Intent Address, which is not known until the Payload is hashed.

Hydrate allows Calls to be configured with predefined replacement commands encoded in a `hydratePayload` byte stream. Unlike the `MalleableSapient`, these replacement commands are included in the Intent configuration and hashed with the payload, reducing the attack surface.

During execution, the Hydrate logic processes the `hydratePayload` to replace calldata, `to`, and `value` fields before processing each Call.

The `hydratePayload` is structured as a byte stream grouped by call index:
- Starts with a 1-byte call index (`tindex`)
- Followed by hydration commands for that call
- Each command starts with a 1-byte flag (type in top nibble, data source in bottom nibble)
- A `SIGNAL_NEXT_HYDRATE` (0x00) ends the current call's section; if more bytes remain, the next byte is the next call index

Address sources: All address parameters can reference `address(this)`, `msg.sender`, `tx.origin`, or a predefined address encoded in the `hydratePayload`.

The Hydrator logic supports the following replacements:

- Calldata (with byte offset):
  - address (any address source)
  - balance (any address source)
  - ERC20(token).balanceOf(any address source)
  - ERC20(token).allowance(owner, spender) where owner and spender are any address source
- To:
  - any address source
- Value:
  - balance of any address source

#### MalleableSapient

[MalleableSapient.sol](src/modules/MalleableSapient.sol) implements the [ISapient interface](https://github.com/0xsequence/wallet-contracts-v3/blob/master/src/modules/interfaces/ISapient.sol) used by Sequence Wallets to support singleton counter factual configurations derived at runtime.

Sequence Wallets support preauthorization of entire payload digests. This does not support all Trails providers. Some information (e.g. commit / reveal bridges) do not allow the entire payload to be known when constructing the Intent supported Payloads.

By allowing some portions of a Payload to be excluded from the derived configuration image hash, we can break the circular dependency and allow the data to be provided at execution time.

The `MalleableSapient` supports "static sections" of payload calldata which roll up to the image hash, and "repeat sections" which require two sections of payload calldata match. Any unconfigured section is considered a "malleable section" and is excluded from validation.

> [!CAUTION]
> Care must be taken not to relax the validation too much. Any malleable field is effectively open to attack, as the wallet will approve any value in an malleable section. malleable sections should only be used for data that is able to be validated during execution.

Using Hydrate logic via the `HydrateProxy` is preferrable over using the `MalleableSapient`. Both features can be used in conjunction.

#### RequireUtils

[RequireUtils.sol](src/modules/RequireUtils.sol) allows a Payload to support preconditions, by reverting when not met.

To use RequireUtils in a Payload, encode the precondition Call as follows:

```
to: RequireUtils (or implementation)
data: abi.encode as normal
behaviourOnError: BEHAVIOR_REVERT_ON_ERROR
onlyFallback: false
```

`BEHAVIOR_REVERT_ON_ERROR` ensures the transaction reverts and does not consume the Payload's nonce.

`onlyFallback` can be set to `true` for more complex interactions such as post-condition validation.

#### Sweep

[Sweep](src/modules/Sweep.sol) allows the entire balance (ERC20, address(this).balance) to be sent to another address.

## Glossary

| Term           | Definition                                                     |
| -------------- | -------------------------------------------------------------- |
| Intent         | The desired Trails interaction. e.g. (swap X->Y)               |
| Intent Address | The counter factual address supporting the Intent.             |
| Payload        | A collection of batched calls with error and fallover support. |
| Call           | One of the batched calls.                                      |
| Sweep          | Transfer tokens up to the current balance.                     |

## Security Considerations

### Call Context

All functions are able to be used from the `TrailsUtils` context via a call from the Intent Address via a `delegatecall`.

`TrailsUtils` supports the `handleSequenceDelegateCall` interface, allowing an Intent to interact within it's own context. This interface is required to support the Sequence Wallet wrapping of delegatecalls. This pattern exposes all functions on `TrailsUtils`.

Delegatecalls from `TrailsUtils` via the `HydrateProxy` execution logic, are only allowed in a nested delegatecall context. The `TrailsUtils` will not process a delegatecall when executing from the context of it's own address.

Any funds accumulated in the `TrailsUtils` context, via a `call` should be swept during batched execution. Remaining funds are to be considered lost.

### Intent Security

The Trails contracts are flexible in what they allow a configuration to represent. Misuse can cause an Intent to be exploitable.

`RequireUtils`, `HydrateProxy` and `MalleableSapient` are tools to help create functionally complete and secure Intent configurations. The actual creation of the configuration must be done with care and is out of scope of this repository.

### Token Handling

All ERC20 operations use OpenZeppelin's SafeERC20.

While the tools in this repository do not directly support non-standard tokens, it's possible for creafully constructed Intents to support them within the wider Trails system.

### State

`TrailsUtils` is stateless and ownerless.
