// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { IPeripheryImmutableState } from
    "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { OracleLibrary } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

import { CollarBaseIntegrationTestConfig } from "./BaseIntegration.t.sol";

import { ConfigHub } from "../../../src/ConfigHub.sol";

abstract contract CollarIntegrationPriceManipulation is CollarBaseIntegrationTestConfig {
    using SafeERC20 for IERC20;

    function getCurrentAssetPrice() internal view returns (uint) {
        address baseToken = address(pair.underlying);
        address quoteToken = address(pair.cashAsset);

        address uniV3Factory = IPeripheryImmutableState(swapRouterAddress).factory();
        IUniswapV3Pool pool =
            IUniswapV3Pool(IUniswapV3Factory(uniV3Factory).getPool(baseToken, quoteToken, pair.oracleFeeTier));

        (, int24 tick,,,,,) = pool.slot0();

        uint128 baseTokenAmount = 1e18;

        return OracleLibrary.getQuoteAtTick(tick, baseTokenAmount, baseToken, quoteToken);
    }

    function manipulatePriceGradually(uint amountToSwap, bool swapCash, uint targetPrice, bool isFuzzTest)
        internal
    {
        uint steps = 5;
        uint amountPerStep = amountToSwap / steps;

        for (uint i = 0; i < steps; i++) {
            swapAsWhale(amountPerStep, swapCash);
            skip(3 minutes); // Advance time by 3 minutes

            uint currentPrice = getCurrentAssetPrice();
            if ((swapCash && currentPrice >= targetPrice) || (!swapCash && currentPrice <= targetPrice)) {
                break;
            }
        }

        // We can add a simple log here to see the final price achieved
        console.log("Final price after manipulation: %d", getCurrentAssetPrice());
        if (!isFuzzTest) {
            assertEq(getCurrentAssetPrice(), targetPrice);
        }
    }

    function _manipulatePriceDownwardPastPutStrike(uint amountToSwap, bool isFuzzTest, uint targetPrice)
        internal
    {
        manipulatePriceGradually(amountToSwap, false, targetPrice, isFuzzTest);
    }

    function _manipulatePriceDownwardShortOfPutStrike(uint amountToSwap, bool isFuzzTest, uint targetPrice)
        internal
        returns (uint)
    {
        manipulatePriceGradually(amountToSwap, false, targetPrice, isFuzzTest);
        return getCurrentAssetPrice();
    }

    function _manipulatePriceUpwardPastCallStrike(uint amountToSwap, bool isFuzzTest, uint targetPrice)
        internal
    {
        manipulatePriceGradually(amountToSwap, true, targetPrice, isFuzzTest);
    }

    function _manipulatePriceUpwardShortOfCallStrike(uint amountToSwap, bool isFuzzTest, uint targetPrice)
        internal
        returns (uint)
    {
        manipulatePriceGradually(amountToSwap, true, targetPrice, isFuzzTest);
        return getCurrentAssetPrice();
    }

    function swapAsWhale(uint amount, bool swapCash) internal {
        uint currentPrice = getCurrentAssetPrice();
        console.log("Current price of underlying in cashAsset before swap: %d", currentPrice);

        IV3SwapRouter.ExactInputSingleParams memory swapParams = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: swapCash ? address(pair.cashAsset) : address(pair.underlying),
            tokenOut: swapCash ? address(pair.underlying) : address(pair.cashAsset),
            fee: 3000,
            recipient: whale,
            amountIn: amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        startHoax(whale);
        IERC20(swapParams.tokenIn).forceApprove(swapRouterAddress, amount);
        IV3SwapRouter(payable(swapRouterAddress)).exactInputSingle(swapParams);
        vm.stopPrank();

        currentPrice = getCurrentAssetPrice();
        console.log("Current price of underlying in cashAsset after swap: %d", currentPrice);
    }
}
