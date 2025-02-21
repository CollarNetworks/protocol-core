// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { ITakerOracle } from "../../../src/interfaces/ITakerOracle.sol";

library PriceMovementHelper {
    using SafeERC20 for IERC20;

    // Price movement
    uint constant STEPS = 20;
    // 15 minutes, to allow for longer TWAP windows
    uint constant STEP_DELAY = 900 seconds;
    uint constant BIPS_BASE = 10_000;

    function moveToTargetPrice(
        Vm vm,
        address swapRouter,
        address whale,
        IERC20 cashAsset,
        IERC20 underlying,
        ITakerOracle oracle,
        uint targetPrice,
        uint cashPerStep,
        uint24 poolFee
    ) internal {
        uint currentPrice = oracle.currentPrice();
        bool increasePrice = targetPrice > currentPrice;
        uint underlyingStepAmount = oracle.convertToBaseAmount(cashPerStep, currentPrice);

        for (uint i = 0; i < STEPS; i++) {
            if (increasePrice) {
                swapCash(vm, swapRouter, whale, cashAsset, underlying, cashPerStep, poolFee);
            } else {
                swapUnderlying(vm, swapRouter, whale, cashAsset, underlying, underlyingStepAmount, poolFee);
            }
            vm.warp(block.timestamp + STEP_DELAY);

            currentPrice = oracle.currentPrice();

            if (increasePrice ? currentPrice >= targetPrice : currentPrice <= targetPrice) {
                break;
            }
        }
        require(
            increasePrice ? currentPrice >= targetPrice : currentPrice <= targetPrice,
            "target price not reached"
        );
    }

    function swapCash(
        Vm vm,
        address swapRouter,
        address whale,
        IERC20 cashAsset,
        IERC20 underlying,
        uint amount,
        uint24 poolFee
    ) private {
        vm.startPrank(whale);
        cashAsset.forceApprove(swapRouter, amount);

        IV3SwapRouter(payable(swapRouter)).exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: address(cashAsset),
                tokenOut: address(underlying),
                fee: poolFee,
                recipient: whale,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();
    }

    function swapUnderlying(
        Vm vm,
        address swapRouter,
        address whale,
        IERC20 cashAsset,
        IERC20 underlying,
        uint amount,
        uint24 poolFee
    ) private {
        vm.startPrank(whale);
        underlying.forceApprove(swapRouter, amount);

        IV3SwapRouter(payable(swapRouter)).exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: address(underlying),
                tokenOut: address(cashAsset),
                fee: poolFee,
                recipient: whale,
                amountIn: amount,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();
    }
}
