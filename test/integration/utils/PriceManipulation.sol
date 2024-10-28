// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { ITakerOracle } from "../../../src/interfaces/ITakerOracle.sol";

library PriceManipulationLib {
    using SafeERC20 for IERC20;

    // Price movement configuration
    uint constant STEPS = 5;
    uint constant STEP_DELAY = 3 minutes;
    uint constant MAX_ATTEMPTS = 5;
    uint constant BIPS_BASE = 10_000;

    // Initial swap amounts (from proven fork tests) (this should ptentially move outside this lib since its pair dependant)
    uint constant AMOUNT_FOR_CALL_STRIKE = 1_000_000e6; // Amount in USDC to move past call strike
    uint constant AMOUNT_FOR_PUT_STRIKE = 250 ether; // Amount in WETH to move past put strike
    uint constant AMOUNT_FOR_PARTIAL_MOVE = 600_000e6; // Amount in USDC to move partially up

    function movePriceUpPastCallStrike(
        Vm vm,
        address swapRouter,
        address whale,
        IERC20 cashAsset,
        IERC20 underlying,
        ITakerOracle oracle,
        uint callStrikePercent,
        uint24 poolFee
    ) external returns (uint finalPrice) {
        uint currentPrice = oracle.currentPrice();
        uint targetPrice = (currentPrice * callStrikePercent / BIPS_BASE) + 1;

        return moveToTargetPrice(
            vm,
            swapRouter,
            whale,
            cashAsset,
            underlying,
            oracle,
            targetPrice,
            true,
            AMOUNT_FOR_CALL_STRIKE,
            poolFee
        );
    }

    function movePriceDownPastPutStrike(
        Vm vm,
        address swapRouter,
        address whale,
        IERC20 cashAsset,
        IERC20 underlying,
        ITakerOracle oracle,
        uint putStrikePercent,
        uint24 poolFee
    ) external returns (uint finalPrice) {
        uint currentPrice = oracle.currentPrice();
        uint targetPrice = (currentPrice * putStrikePercent / BIPS_BASE) - 1;

        return moveToTargetPrice(
            vm,
            swapRouter,
            whale,
            cashAsset,
            underlying,
            oracle,
            targetPrice,
            false,
            AMOUNT_FOR_PUT_STRIKE,
            poolFee
        );
    }

    function movePriceUpPartially(
        Vm vm,
        address swapRouter,
        address whale,
        IERC20 cashAsset,
        IERC20 underlying,
        ITakerOracle oracle,
        uint24 poolFee
    ) external returns (uint finalPrice) {
        vm.startPrank(whale);
        cashAsset.forceApprove(swapRouter, AMOUNT_FOR_PARTIAL_MOVE);

        IV3SwapRouter(payable(swapRouter)).exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: address(cashAsset),
                tokenOut: address(underlying),
                fee: poolFee,
                recipient: whale,
                amountIn: AMOUNT_FOR_PARTIAL_MOVE,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 3 minutes);
        return oracle.currentPrice();
    }

    function moveToTargetPrice(
        Vm vm,
        address swapRouter,
        address whale,
        IERC20 cashAsset,
        IERC20 underlying,
        ITakerOracle oracle,
        uint targetPrice,
        bool _swapCash,
        uint initialAmount,
        uint24 poolFee
    ) private returns (uint finalPrice) {
        uint swapAmount = initialAmount;
        uint currentPrice = oracle.currentPrice();

        for (uint i = 0; i < MAX_ATTEMPTS; i++) {
            manipulatePriceInSteps(
                vm, swapRouter, whale, cashAsset, underlying, swapAmount, _swapCash, STEPS, poolFee
            );
            currentPrice = oracle.currentPrice();

            if ((_swapCash && currentPrice >= targetPrice) || (!_swapCash && currentPrice <= targetPrice)) {
                break;
            }

            swapAmount = swapAmount * 2;
        }

        return oracle.currentPrice();
    }

    function manipulatePriceInSteps(
        Vm vm,
        address swapRouter,
        address whale,
        IERC20 cashAsset,
        IERC20 underlying,
        uint totalAmount,
        bool _swapCash,
        uint steps,
        uint24 poolFee
    ) private {
        uint amountPerStep = totalAmount / steps;
        for (uint i = 0; i < steps; i++) {
            if (_swapCash) {
                swapCash(vm, swapRouter, whale, cashAsset, underlying, amountPerStep, poolFee);
            } else {
                swapUnderlying(vm, swapRouter, whale, cashAsset, underlying, amountPerStep, poolFee);
            }
            vm.warp(block.timestamp + STEP_DELAY);
        }
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
