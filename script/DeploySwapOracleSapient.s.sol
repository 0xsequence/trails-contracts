// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {SwapOracleSapient} from "src/modules/SwapOracleSapient.sol";

contract DeploySwapOracleSapient is Script {
    // 1inch Spot Price Aggregator - same address on all chains
    address constant ONEINCH_ORACLE = 0x00000000000D6FFc74A8feb35aF5827bf57f6786;
    // Default 3% max slippage
    uint256 constant MAX_SLIPPAGE_BPS = 300;

    function run() external {
        vm.startBroadcast();

        SwapOracleSapient sapient = new SwapOracleSapient(ONEINCH_ORACLE, MAX_SLIPPAGE_BPS);

        console.log("SwapOracleSapient deployed at:", address(sapient));
        console.log("  priceOracle:", address(sapient.priceOracle()));
        console.log("  maxSlippageBps:", sapient.maxSlippageBps());

        vm.stopBroadcast();
    }
}
