// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {SwapOracleSapient} from "src/modules/SwapOracleSapient.sol";

contract DeploySwapOracleSapient is Script {
    // Uniswap V3 Factory on Base
    address constant UNISWAP_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    // Default 3% max slippage
    uint256 constant MAX_SLIPPAGE_BPS = 300;

    function run() external {
        vm.startBroadcast();

        SwapOracleSapient sapient = new SwapOracleSapient(UNISWAP_V3_FACTORY, MAX_SLIPPAGE_BPS);

        console.log("SwapOracleSapient deployed at:", address(sapient));
        console.log("  factory:", sapient.factory());
        console.log("  maxSlippageBps:", sapient.maxSlippageBps());

        vm.stopBroadcast();
    }
}
