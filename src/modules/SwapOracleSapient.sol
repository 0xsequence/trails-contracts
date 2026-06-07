// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {ISapient} from "wallet-contracts-v3/modules/interfaces/ISapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

interface IUniswapV3Factory {
  function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

interface IUniswapV3Pool {
  function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked);
}

/// @title SwapOracleSapient
/// @notice ISapient that validates same-chain swap output against a Uniswap V3 spot price.
/// @dev Reads sqrtPriceX96 from the best available Uniswap V3 pool for the token pair.
///      Tries fee tiers 500, 3000, 10000 in order, uses the first pool with liquidity.
contract SwapOracleSapient is ISapient {
  error NonTransactionPayload();
  error BelowOracleFloor(uint256 required, uint256 provided);
  error NoPoolFound();

  address public immutable factory;
  uint256 public immutable maxSlippageBps;

  uint24[3] private FEE_TIERS = [uint24(500), 3000, 10000];

  constructor(address _factory, uint256 _maxSlippageBps) {
    factory = _factory;
    maxSlippageBps = _maxSlippageBps;
  }

  /// @inheritdoc ISapient
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

    uint256 rate = _getRate(tokenIn, tokenOut);
    uint256 minOutput = (inputAmount * rate * (10000 - maxSlippageBps)) / (10000 * 1e18);
    if (outputAmount < minOutput) {
      revert BelowOracleFloor(minOutput, outputAmount);
    }

    return _imageHash(tokenIn, tokenOut, recipient);
  }

  function _getRate(address tokenIn, address tokenOut) internal view returns (uint256) {
    uint160 sqrtPriceX96;
    bool found;

    for (uint256 i; i < 3; i++) {
      address pool = IUniswapV3Factory(factory).getPool(tokenIn, tokenOut, FEE_TIERS[i]);
      if (pool != address(0)) {
        (sqrtPriceX96,,,,,, ) = IUniswapV3Pool(pool).slot0();
        if (sqrtPriceX96 != 0) {
          found = true;
          break;
        }
      }
    }
    if (!found) revert NoPoolFound();

    uint256 sqr = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
    if (tokenIn < tokenOut) {
      return (sqr * 1e18) >> 192;
    } else {
      return ((1 << 192) * 1e18) / sqr;
    }
  }

  function imageHash(address tokenIn, address tokenOut, address recipient) external view returns (bytes32) {
    return _imageHash(tokenIn, tokenOut, recipient);
  }

  function _imageHash(address tokenIn, address tokenOut, address recipient) internal view returns (bytes32) {
    return keccak256(abi.encode("SwapOracleSapient", factory, maxSlippageBps, tokenIn, tokenOut, recipient));
  }
}
