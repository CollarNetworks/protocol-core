// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SwapperUniV3 } from "../../src/SwapperUniV3.sol";
import { UniswapNewPoolHelper } from "../utils/UniswapNewPoolHelper.sol";
import { Const } from "../../script/utils/Const.sol";

abstract contract SwapperUniV3_BaseForkTest is Test, UniswapNewPoolHelper {
    SwapperUniV3 public swapper;

    address router;
    address positionManager;
    int24 tickSpacing;
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

    function setupNewTokensAndPool() internal {
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

contract SwapperUniV3_ArbiMain_ForkTest is SwapperUniV3_BaseForkTest {
    function setUp() public virtual {
        vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_RPC"), 242_273_401);
        router = Const.ArbiMain_UniRouter;
        positionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    }

    function setupUSDCWETH() internal {
        tokenIn = Const.ArbiMain_WETH;
        tokenOut = Const.ArbiMain_USDC;
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

contract SwapperUniV3_ArbiSepolia_ForkTest is SwapperUniV3_BaseForkTest {
    function setUp() public virtual {
        vm.createSelectFork(vm.envString("ARBITRUM_SEPOLIA_RPC"), 72_779_252);
        router = Const.ArbiSep_UniRouter;
        positionManager = Const.ArbiSep_UniPosMan;
    }

    function test_USDCWBTC_500() public virtual {
        tokenIn = 0x0d64F70fAd5897d752c6e9e9a80ac3C978BF6897; // WBTC arbi-sep
        tokenOut = 0xbDCc1D2ADE76E4A02539674D6D03E4bf571Da712; // USDC arbi-sep
        amountIn = 1e8; // WBTC 8 decimals
        feeTier = 500;
        expectedAmountOut = 56_224_329_741; // 56K 6 decimals
        basicTests();
    }
}

contract SwapperUniV3_OPBaseMain_ForkTest is SwapperUniV3_BaseForkTest {
    function setUp() public virtual {
        vm.createSelectFork(vm.envString("OPBASE_MAINNET_RPC"), 25_666_192);
        router = Const.OPBaseMain_UniRouter;
        positionManager = 0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1;
    }

    function setupUSDCWETH() internal {
        tokenIn = Const.OPBaseMain_WETH;
        tokenOut = Const.OPBaseMain_USDC;
        amountIn = 1 ether;
    }

    function test_USDCWETH_500() public {
        setupUSDCWETH();
        feeTier = 500;
        expectedAmountOut = 3_113_223_630;
        basicTests();
    }

    function test_USDCWETH_100() public {
        setupUSDCWETH();
        feeTier = 100;
        expectedAmountOut = 3_113_540_128;
        basicTests();
    }

    function test_USDCWETH_3000() public {
        setupUSDCWETH();
        feeTier = 3000;
        expectedAmountOut = 3_106_415_569;
        basicTests();
    }

    function test_USDCWETH_10000() public {
        setupUSDCWETH();
        feeTier = 10_000;
        expectedAmountOut = 3_054_986_931;
        basicTests();
    }

    function test_WETHUSDC() public {
        setupUSDCWETH();
        feeTier = 500;
        (tokenIn, tokenOut) = (tokenOut, tokenIn); // Swap USDC and WETH
        amountIn = 3_116_210_000; // 1 ETH worth of USDC
        expectedAmountOut = 999_938_803_835_294_949; // 0.998 ETH
        basicTests();
    }
}

contract SwapperUniV3_OPBaseSep_ForkTest is SwapperUniV3_BaseForkTest {
    function setUp() public {
        vm.createSelectFork(vm.envString("OPBASE_SEPOLIA_RPC"), 21_176_690);
        router = Const.OPBaseSep_UniRouter;
        positionManager = Const.OPBaseSep_UniPosMan;
    }
}
