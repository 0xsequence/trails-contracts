# Trails Contracts

Smart contracts for [Sequence Trails](https://trails.build).

## Contracts

### TrailsUtils

All modules are combined into a single [TrailsUtils.sol](src/TrailsUtils.sol) to reduce gas costs.

### Modules

#### MalleableSapient

[MalleableSapient.sol](src/modules/MalleableSapient.sol) implements the [ISapient interface](https://github.com/0xsequence/wallet-contracts-v3/blob/master/src/modules/interfaces/ISapient.sol) used by Sequence Wallets to support singleton counter factual configurations derived at runtime.

Sequence Wallets support preauthorization of entire payload digests. This does not support all Trails providers. Some information (e.g. commit / reveal bridges) do not allow the entire payload to be known when constructing the Intent supported Payloads.

By allowing some portions of a Payload to be excluded, we can break the circular dependency and allow the data to be provided at execution time.

> [!CAUTION]
> Care must be taken not to relax the validation too much. Any Malleable field is effectively open to attack, as the wallet will approve any value in a Malleable section. Malleable sections should only be used for data that is able to be validated during execution.

Using Hydrate logic via the `SharedProxy` is preferrable over using the `MalleableSigner`.

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

#### SharedProxy

[SharedProxy.sol](src/modules/SharedProxy.sol) has multiple capabilities.

##### Hydrate

Some Payload Calls require parameter encoding that is only available during execution. For example, a Call may require the ERC20 balance to be encoded, but the exact value may change due to slippage. Payloads may also have the circular dependency issue where the Call must encode the Intent Address, which is not known until the Payload is hashed.

Hydrate allows Calls to be configured which predefined replacement identifiers. Unlike the `MalleableSigner`, these replacement identifiers are encoded in the Payload and included in the Intent configuration, reducing the attack surface.

During execution, the Hydrate logic will replace the calldata with the predefined identifiers before processing the Call.

The Hydrator logic supports the replacement with:

- Calldata:
  - address(self)
  - msg.sender
  - tx.origin
  - ERC20(token).balanceOf(address(self))
  - ERC20(token).balanceOf(msg.sender)
  - ERC20(token).balanceOf(tx.origin)
  - ERC20(token).balanceOf(predefined_address)
  - address(self).balance
  - msg.sender.balance
  - tx.origin.balance
  - address(predefined_address).balance
- To:
  - msg.sender
  - tx.origin
- Value:
  - msg.sender.balance

##### Sweep

The `SharedProxy` also supports `Sweep` logic, allowing the entire balance (ERC20, address(this).balance) to another address.

This is only accessible via `hydrateExecuteAndSweep`.

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

All functions are intended to be used from the `TrailsUtils` context via a call from the Intent Address.

Delegatecall via the Intent Address is only able to access `hydrateExecute`. This is due to the Sequence Wallet wrapping of delegatecalls within `handleSequenceDelegateCall`.

### Intent Security

The Trails contracts are flexible in what they allow a configuration to represent. Misuse can cause an Intent to be exploitable.

`RequireUtils`, `Hydrate` and `MalleableSapient` are tools to help create functionally complete and secure Intent configurations. The actual creation of the configuration must be done with care and is out of scope of this repository.

### Token Handling

All ERC20 operations use OpenZeppelin's SafeERC20.

While the tools in this repository do not directly support non-standard tokens, it's possible for creafully constructed Intents to support them within the wider Trails system.

### State

`TrailsUtils` is stateless and ownerless.
