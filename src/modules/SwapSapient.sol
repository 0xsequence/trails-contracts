// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

interface ISpotPriceOracle {
  function getRate(address srcToken, address dstToken, bool useWrappers) external view returns (uint256 weightedRate);
}

/// @title SwapSapient
/// @notice ISapient that validates same-chain swap output against an on-chain price oracle.
/// @dev Reads the 1inch Spot Price Aggregator (or any compatible oracle) to enforce a
///      minimum output amount. Does NOT parse swap calldata - that's handled by
///      MalleableSapient in a co-signing configuration.
///
///      The imageHash commits to: oracle, slippage, tokenIn, tokenOut, recipient.
///      Amounts are validated at runtime but excluded from imageHash (vary per execution).
contract SwapSapient is ISapient {
  error NonTransactionPayload();
  error BelowOracleFloor(uint256 required, uint256 provided);
  error InvalidOracleRate();

  /// @notice On-chain price oracle (e.g., 1inch Spot Price Aggregator).
  address public immutable priceOracle;

  /// @notice Maximum allowed slippage in basis points (e.g., 300 = 3%).
  uint256 public immutable maxSlippageBps;

  constructor(address _priceOracle, uint256 _maxSlippageBps) {
    priceOracle = _priceOracle;
    maxSlippageBps = _maxSlippageBps;
  }

  /// @inheritdoc ISapient
  /// @dev `signature` is ABI-encoded as:
  ///   (address tokenIn, address tokenOut, address recipient,
  ///    uint256 inputAmount, uint256 outputAmount)
  ///
  ///   The sapient verifies outputAmount >= inputAmount * oracleRate * (1 - slippage).
  ///   tokenIn, tokenOut, and recipient are committed in the imageHash (static per PDA).
  ///   inputAmount and outputAmount are validated at runtime (vary per execution).
  function recoverSapientSignature(
    Payload.Decoded calldata payload,
    bytes calldata signature
  ) external view returns (bytes32) {
    if (payload.kind != Payload.KIND_TRANSACTIONS) {
      revert NonTransactionPayload();
    }

    (
      address tokenIn,
      address tokenOut,
      address recipient,
      uint256 inputAmount,
      uint256 outputAmount
    ) = abi.decode(signature, (address, address, address, uint256, uint256));

    uint256 rate = ISpotPriceOracle(priceOracle).getRate(tokenIn, tokenOut, true);
    if (rate == 0) {
      revert InvalidOracleRate();
    }

    uint256 minOutput = (inputAmount * rate * (10000 - maxSlippageBps)) / (10000 * 1e18);
    if (outputAmount < minOutput) {
      revert BelowOracleFloor(minOutput, outputAmount);
    }

    return _imageHash(tokenIn, tokenOut, recipient);
  }

  /// @notice Computes the fixed imageHash for a same-chain swap PDA.
  function imageHash(
    address tokenIn,
    address tokenOut,
    address recipient
  ) external view returns (bytes32) {
    return _imageHash(tokenIn, tokenOut, recipient);
  }

  function _imageHash(
    address tokenIn,
    address tokenOut,
    address recipient
  ) internal view returns (bytes32) {
    return keccak256(
      abi.encode("SwapSapient", priceOracle, maxSlippageBps, tokenIn, tokenOut, recipient)
    );
  }
}
