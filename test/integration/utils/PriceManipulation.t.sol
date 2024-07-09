// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { CollarEngine } from "../../../src/implementations/CollarEngine.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { IPeripheryImmutableState } from
    "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import { TestPriceOracle } from "../../utils/TestPriceOracle.sol";
import { CollarBaseIntegrationTestConfig } from "./BaseIntegration.t.sol";

abstract contract CollarIntegrationPriceManipulation is CollarBaseIntegrationTestConfig {
    using SafeERC20 for IERC20;

    uint public constant PRICE_DEVIATION_TOLERANCE = 1000; // 10% in basis points

    function getCurrentAssetPrice() internal view returns (uint) {
        address uniV3Factory = IPeripheryImmutableState(engine.univ3SwapRouter()).factory();
        return TestPriceOracle.getUnsafePrice(address(collateralAsset), address(cashAsset), uniV3Factory);
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
        console.log("Current price of collateralAsset in cashAsset before swap: %d", currentPrice);

        IV3SwapRouter.ExactInputSingleParams memory swapParams = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: swapCash ? address(cashAsset) : address(collateralAsset),
            tokenOut: swapCash ? address(collateralAsset) : address(cashAsset),
            fee: 3000,
            recipient: whale,
            amountIn: amount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        startHoax(whale);
        IERC20(swapParams.tokenIn).forceApprove(engine.univ3SwapRouter(), amount);
        IV3SwapRouter(payable(engine.univ3SwapRouter())).exactInputSingle(swapParams);
        vm.stopPrank();

        currentPrice = getCurrentAssetPrice();
        console.log("Current price of collateralAsset in cashAsset after swap: %d", currentPrice);
    }
}
