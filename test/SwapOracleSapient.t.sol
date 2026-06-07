// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {SwapOracleSapient} from "src/modules/SwapOracleSapient.sol";
import {Payload} from "wallet-contracts-v3/modules/Payload.sol";

interface IUniswapV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

interface IUniswapV3Pool {
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16, uint16, uint16, uint8, bool);
}

contract SwapOracleSapientForkTest is Test {
    // Uniswap V3 Factory on Base
    address constant UNISWAP_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH_BASE = 0x4200000000000000000000000000000000000006;

    SwapOracleSapient sapient;

    function setUp() external {
        sapient = new SwapOracleSapient(UNISWAP_V3_FACTORY, 300);
    }

    function test_v3PoolExists() external view {
        address pool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(USDC_BASE, WETH_BASE, 500);
        assertTrue(pool != address(0), "USDC/WETH 500 pool should exist");
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        assertGt(uint256(sqrtPriceX96), 0, "sqrtPriceX96 should be non-zero");
        console.log("USDC/WETH pool:", pool);
        console.log("sqrtPriceX96:", uint256(sqrtPriceX96));
    }

    function test_imageHash() external view {
        address recipient = address(0xBEEF);
        bytes32 hash = sapient.imageHash(USDC_BASE, WETH_BASE, recipient);
        console.log("imageHash:");
        console.logBytes32(hash);
        assertNotEq(hash, bytes32(0), "imageHash should not be zero");
    }

    function test_imageHash_deterministic() external view {
        address recipient = address(0xBEEF);
        bytes32 expected = keccak256(abi.encode(
            "SwapOracleSapient", UNISWAP_V3_FACTORY, uint256(300), USDC_BASE, WETH_BASE, recipient
        ));
        bytes32 actual = sapient.imageHash(USDC_BASE, WETH_BASE, recipient);
        assertEq(actual, expected, "imageHash should match manual computation");
    }

    function test_recoverSapientSignature_validPrice() external view {
        // Get rate from V3 pool to compute a fair output
        address pool = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(USDC_BASE, WETH_BASE, 500);
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();

        // USDC < WETH by address, so rate = (sqr * 1e18) >> 192
        uint256 sqr = uint256(sqrtPriceX96) * uint256(sqrtPriceX96);
        uint256 rate = (sqr * 1e18) >> 192;
        console.log("V3 rate:", rate);

        uint256 inputAmount = 1_000_000; // 1 USDC
        uint256 fairOutput = (inputAmount * rate * 9700) / (10000 * 1e18);
        console.log("Fair output (WETH wei):", fairOutput);

        Payload.Decoded memory payload = _buildPayload();

        address recipient = address(0xBEEF);
        bytes memory sig = abi.encode(USDC_BASE, WETH_BASE, recipient, inputAmount, fairOutput);

        bytes32 imgHash = sapient.recoverSapientSignature(payload, sig);
        console.log("recoverSapientSignature returned imageHash:");
        console.logBytes32(imgHash);
        assertNotEq(imgHash, bytes32(0));
    }

    function test_recoverSapientSignature_revertsBelowFloor() external {
        uint256 inputAmount = 1_000_000; // 1 USDC
        uint256 tooLowOutput = 1; // 1 wei WETH - way below fair price

        Payload.Decoded memory payload = _buildPayload();

        address recipient = address(0xBEEF);
        bytes memory sig = abi.encode(USDC_BASE, WETH_BASE, recipient, inputAmount, tooLowOutput);

        vm.expectRevert();
        sapient.recoverSapientSignature(payload, sig);
    }

    function test_revert_noPoolFound() external {
        // Use two random addresses with no V3 pool
        address fakeTokenA = address(0xDEAD);
        address fakeTokenB = address(0xBEEF);

        Payload.Decoded memory payload = _buildPayload();

        bytes memory sig = abi.encode(fakeTokenA, fakeTokenB, address(0xCAFE), uint256(1e18), uint256(1e18));

        vm.expectRevert(SwapOracleSapient.NoPoolFound.selector);
        sapient.recoverSapientSignature(payload, sig);
    }

    function _buildPayload() internal pure returns (Payload.Decoded memory) {
        Payload.Call[] memory calls = new Payload.Call[](1);
        calls[0] = Payload.Call({
            to: WETH_BASE,
            value: 0,
            data: hex"00",
            gasLimit: 0,
            delegateCall: false,
            onlyFallback: false,
            behaviorOnError: Payload.BEHAVIOR_REVERT_ON_ERROR
        });

        return Payload.Decoded({
            kind: Payload.KIND_TRANSACTIONS,
            noChainId: false,
            calls: calls,
            space: 0,
            nonce: 0,
            message: bytes(""),
            imageHash: bytes32(0),
            digest: bytes32(0),
            parentWallets: new address[](0)
        });
    }
}
