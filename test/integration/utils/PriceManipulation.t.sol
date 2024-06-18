// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { CollarEngine } from "../../../src/implementations/CollarEngine.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IV3SwapRouter } from "@uniswap/v3-swap-contracts/interfaces/IV3SwapRouter.sol";
import { CollarBaseIntegrationTestConfig } from "./BaseIntegration.t.sol";

abstract contract CollarIntegrationPriceManipulation is CollarBaseIntegrationTestConfig {
    using SafeERC20 for IERC20;

    function _manipulatePriceDownwardPastPutStrike(uint amountToSwap, bool isFuzzTest, uint targetPrice)
        internal
    {
        // Trade on Uniswap to make the price go down past the put strike price .9 * COLLATERAL_PRICE_ON_BLOCK
        swapAsWhale(amountToSwap, false);
        if (!isFuzzTest) {
            assertEq(
                CollarEngine(engine).getCurrentAssetPrice(collateralAssetAddress, cashAssetAddress),
                targetPrice
            );
        }
    }

    function _manipulatePriceDownwardShortOfPutStrike(uint amountToSwap, bool isFuzzTest, uint targetPrice)
        internal
        returns (uint finalPrice)
    {
        // Trade on Uniswap to make the price go down but not past the put strike price .9 *
        // COLLATERAL_PRICE_ON_BLOCK
        swapAsWhale(amountToSwap, false);
        finalPrice = CollarEngine(engine).getCurrentAssetPrice(collateralAssetAddress, cashAssetAddress);
        if (!isFuzzTest) {
            assertEq(
                CollarEngine(engine).getCurrentAssetPrice(collateralAssetAddress, cashAssetAddress),
                targetPrice
            );
        } else {
            console.log("Current price of collateralAsset in cashAsset after swap: %d", targetPrice);
        }
    }

    function _manipulatePriceUpwardPastCallStrike(uint amountToSwap, bool isFuzzTest, uint targetPrice)
        internal
    {
        // Trade on Uniswap to make the price go up past the call strike price 1.1 * COLLATERAL_PRICE_ON_BLOCK
        swapAsWhale(amountToSwap, true);
        if (!isFuzzTest) {
            assertEq(
                CollarEngine(engine).getCurrentAssetPrice(collateralAssetAddress, cashAssetAddress),
                targetPrice
            );
        }
    }

    function _manipulatePriceUpwardShortOfCallStrike(uint amountToSwap, bool isFuzzTest, uint targetPrice)
        internal
        returns (uint finalPrice)
    {
        // Trade on Uniswap to make the price go up but not past the call strike price 1.1 *
        // COLLATERAL_PRICE_ON_BLOCK
        swapAsWhale(amountToSwap, true);
        finalPrice = CollarEngine(engine).getCurrentAssetPrice(collateralAssetAddress, cashAssetAddress);
        if (!isFuzzTest) {
            assertEq(
                CollarEngine(engine).getCurrentAssetPrice(collateralAssetAddress, cashAssetAddress),
                targetPrice
            );
        }
    }

    function swapAsWhale(uint amount, bool swapCash) internal {
        // Trade on Uniswap to _manipulate the price
        uint currentPrice =
            CollarEngine(engine).getCurrentAssetPrice(collateralAssetAddress, cashAssetAddress);
        console.log("Current price of collateralAsset in cashAsset before swap: %d", currentPrice);

        uint poolBalanceCollateral = collateralAsset.balanceOf(uniV3Pool);
        uint poolBalanceCash = cashAsset.balanceOf(uniV3Pool);
        // build the swap transaction
        IV3SwapRouter.ExactInputSingleParams memory swapParams = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: cashAssetAddress,
            tokenOut: collateralAssetAddress,
            fee: 3000,
            recipient: address(this),
            amountIn: amount,
            amountOutMinimum: 100,
            sqrtPriceLimitX96: 0
        });
        startHoax(whale);
        if (swapCash) {
            cashAsset.forceApprove(CollarEngine(engine).dexRouter(), amount);
            swapParams.tokenIn = cashAssetAddress;
            swapParams.tokenOut = collateralAssetAddress;
            // execute the swap
            // we're not worried about slippage here
            IV3SwapRouter(payable(CollarEngine(engine).dexRouter())).exactInputSingle(swapParams);
        } else {
            collateralAsset.forceApprove(CollarEngine(engine).dexRouter(), amount);

            swapParams.tokenIn = collateralAssetAddress;
            swapParams.tokenOut = cashAssetAddress;
            // execute the swap
            // we're not worried about slippage here
            IV3SwapRouter(payable(CollarEngine(engine).dexRouter())).exactInputSingle(swapParams);
        }

        currentPrice = CollarEngine(engine).getCurrentAssetPrice(collateralAssetAddress, cashAssetAddress);
        poolBalanceCollateral = collateralAsset.balanceOf(uniV3Pool);
        poolBalanceCash = cashAsset.balanceOf(uniV3Pool);
        console.log("Current price of collateralAsset in cashAsset after swap: %d", currentPrice);
    }
}
