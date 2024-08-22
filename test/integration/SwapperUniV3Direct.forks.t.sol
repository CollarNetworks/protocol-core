// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SwapperUniV3 } from "../../src/SwapperUniV3.sol";

import { UniswapNewPoolHelper } from "../utils/UniswapNewPoolHelper.sol";

contract SwapperUniV3_BaseForkTest is Test {
    SwapperUniV3 public swapper;

    address router;
    uint24 feeTier;

    address tokenIn;
    address tokenOut;
    uint amountIn;
    uint expectedAmountOut;

    function basicTests() internal {
        // get tokens
        deal(tokenIn, address(this), amountIn);
        // deploy
        swapper = new SwapperUniV3(router, feeTier);

        // check constructor
        assertEq(swapper.VERSION(), "0.2.0");
        assertEq(address(swapper.uniV3SwapRouter()), router);
        assertEq(swapper.swapFeeTier(), feeTier);

        IERC20(tokenIn).approve(address(swapper), amountIn);
        // check slippage
        // this revert is from Uniswap Router - not from swapper
        vm.expectRevert("Too little received");
        swapper.swap(IERC20(tokenIn), IERC20(tokenOut), amountIn, expectedAmountOut + 1, "");

        // check swap
        uint balanceInBefore = IERC20(tokenIn).balanceOf(address(this));
        uint balanceOutBefore = IERC20(tokenOut).balanceOf(address(this));
        uint amountOut = swapper.swap(IERC20(tokenIn), IERC20(tokenOut), amountIn, expectedAmountOut, "");
        assertEq(amountOut, expectedAmountOut);
        assertEq(IERC20(tokenOut).balanceOf(address(this)) - balanceOutBefore, expectedAmountOut);
        assertEq(balanceInBefore - IERC20(tokenIn).balanceOf(address(this)), amountIn);
    }
}

contract SwapperUniV3_ArbiMain_ForkTest is SwapperUniV3_BaseForkTest {
    function setUp() public virtual {
        vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_RPC"), 242_273_401);
    }

    function setupUSDCWETH() internal {
        router = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        tokenIn = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        tokenOut = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC
        amountIn = 1 ether;
    }

    function test_USDCWETH_500() public {
        setupUSDCWETH();
        feeTier = 500;
        expectedAmountOut = 2_712_591_287;
        basicTests();
    }

    function test_USDCWETH_100() public {
        setupUSDCWETH();
        feeTier = 100;
        expectedAmountOut = 2_604_505_070;
        basicTests();
    }

    function test_USDCWETH_3000() public {
        setupUSDCWETH();
        feeTier = 3000;
        expectedAmountOut = 2_702_238_716;
        basicTests();
    }

    function test_USDCWETH_10000() public {
        setupUSDCWETH();
        feeTier = 10_000;
        expectedAmountOut = 2_648_912_433;
        basicTests();
    }

    function test_WETHUSDC() public {
        setupUSDCWETH();
        feeTier = 500;
        (tokenIn, tokenOut) = (tokenOut, tokenIn); // Swap USDC and WETH
        amountIn = 2_712_591_287; // 1 ETH worth of USDC
        expectedAmountOut = 998_961_362_164_977_913; // 0.998 ETH
        basicTests();
    }
}

contract SwapperUniV3_ArbiSepolia_ForkTest is SwapperUniV3_BaseForkTest, UniswapNewPoolHelper {
    address positionManager;
    int24 tickSpacing;

    function setUp() public {
        vm.createSelectFork(vm.envString("ARBITRUM_SEPOLIA_RPC"), 72_779_252);
    }

    function setupSepolia() internal {
        router = 0x101F443B4d1b059569D643917553c771E1b9663E; // arbi-sep
        positionManager = 0x6b2937Bde17889EDCf8fbD8dE31C3C2a70Bc4d65; // arbi-sep
    }

    function setupUSDCWBTC() internal {
        setupSepolia();
        tokenIn = 0x0d64F70fAd5897d752c6e9e9a80ac3C978BF6897; // WBTC arbi-sep
        tokenOut = 0xbDCc1D2ADE76E4A02539674D6D03E4bf571Da712; // USDC arbi-sep
        amountIn = 1e8; // WBTC 8 decimals
    }

    function setupNewTokensAndPool() internal {
        setupSepolia();
        (tokenIn, tokenOut) = deployTokens();

        uint initialAmount = 10 ether;

        setupNewPool(
            PoolParams({
                token1: tokenIn,
                token2: tokenOut,
                router: router,
                positionManager: positionManager,
                feeTier: feeTier,
                cardinality: 1,
                initialAmount: initialAmount,
                tickSpacing: tickSpacing
            })
        );

        amountIn = 1 ether;
    }

    function test_USDCWBTC_500() public {
        setupUSDCWBTC();
        feeTier = 500;
        expectedAmountOut = 56_224_329_741; // 56K 6 decimals
        basicTests();
    }

    function test_newTokens_500() public {
        feeTier = 500;
        tickSpacing = 10;
        setupNewTokensAndPool();
        expectedAmountOut = 999_450_067_463_638_014; // almost 1e18
        basicTests();
    }

    function test_newTokens_100() public {
        feeTier = 100;
        tickSpacing = 1;
        setupNewTokensAndPool();
        expectedAmountOut = 999_895_001_399_832_390; // almost 1e18
        basicTests();
    }

    function test_newTokens_3000() public {
        feeTier = 3000;
        tickSpacing = 60;
        setupNewTokensAndPool();
        expectedAmountOut = 996_702_347_911_456_766; // almost 1e18
        basicTests();
    }

    function test_newTokens_10000() public {
        feeTier = 10_000;
        tickSpacing = 200;
        setupNewTokensAndPool();
        expectedAmountOut = 989_025_792_331_483_854; // almost 1e18
        basicTests();
    }
}
