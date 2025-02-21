// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { INonfungiblePositionManager } from
    "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IPeripheryImmutableState } from
    "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";
import { CollarOwnedERC20 } from "../utils/CollarOwnedERC20.sol";

contract UniswapNewPoolHelper {
    struct PoolParams {
        address token1;
        address token2;
        address router;
        address positionManager;
        uint24 feeTier;
        uint16 cardinality;
        uint initialAmount;
        int24 tickSpacing;
    }

    function deployTokens() internal returns (address, address) {
        return (
            address(new CollarOwnedERC20(address(this), "Token1", "Token1", 18)),
            address(new CollarOwnedERC20(address(this), "Token2", "Token2", 18))
        );
    }

    function setupNewPool(PoolParams memory params) internal returns (address newPool) {
        address factory = IPeripheryImmutableState(params.router).factory();
        newPool = IUniswapV3Factory(factory).createPool(params.token1, params.token2, params.feeTier);

        // price 1:1, because otherwise liquidity amounts calc is a bit much
        //  if another initial price and liquidity are needed use this: https://uniswapv3book.com/milestone_1/calculating-liquidity.html
        uint160 sqrtPriceX96Tick0 = 79_228_162_514_264_337_593_543_950_336;
        IUniswapV3Pool(newPool).initialize(sqrtPriceX96Tick0);

        provideAmount1to1(params, params.initialAmount);

        // set the cardinality to what is needed
        IUniswapV3Pool(newPool).increaseObservationCardinalityNext(params.cardinality);
    }

    function provideAmount1to1(PoolParams memory params, uint amount) internal {
        CollarOwnedERC20(params.token1).mint(address(this), amount);
        CollarOwnedERC20(params.token2).mint(address(this), amount);

        CollarOwnedERC20(params.token1).approve(address(params.positionManager), amount);
        CollarOwnedERC20(params.token2).approve(address(params.positionManager), amount);

        INonfungiblePositionManager(params.positionManager).mint(
            INonfungiblePositionManager.MintParams({
                token0: params.token1 < params.token2 ? params.token1 : params.token2,
                token1: params.token1 < params.token2 ? params.token2 : params.token1,
                fee: params.feeTier,
                tickLower: -params.tickSpacing,
                tickUpper: params.tickSpacing,
                amount0Desired: amount,
                amount1Desired: amount,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );
    }
}
