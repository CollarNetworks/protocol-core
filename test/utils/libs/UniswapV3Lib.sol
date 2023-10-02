// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {TickMath} from "@uni-v3-core/libraries/TickMath.sol";
import {UniswapV3Factory} from "@uni-v3-core/UniswapV3Factory.sol";
import {PoolAddress} from "@uni-v3-periphery/libraries/PoolAddress.sol";
import {SwapRouter} from "@uni-v3-periphery/SwapRouter.sol";
import {ISwapRouter} from "@uni-v3-periphery/interfaces/ISwapRouter.sol";
import {NonfungiblePositionManager as NFTManager} from "@uni-v3-periphery/NonfungiblePositionManager.sol";
import {INonfungiblePositionManager as INFTManager} from "@uni-v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {MockWeth} from "../mocks/MockWeth.sol";
import {Test} from "@forge-std/Test.sol";

library UniswapV3Math {
    uint24 constant FEE_LOW = 500;
    uint24 constant FEE_MEDIUM = 3000;
    uint24 constant FEE_HIGH = 10_000;

    int24 constant TICK_LOW = 10;
    int24 constant TICK_MEDIUM = 60;
    int24 constant TICK_HIGH = 200;

    function EVEN_PRICE() public pure returns (uint160) {
        return encodePriceSqrt(1, 1);
    }

    function feeToTick(uint24 fee) public pure returns (int24 tick) {
        require(fee == FEE_LOW || fee == FEE_MEDIUM || fee == FEE_HIGH, "Invalid fee tier");

        if (fee == FEE_LOW) return TICK_LOW;
        if (fee == FEE_MEDIUM) return TICK_MEDIUM;
        if (fee == FEE_HIGH) return TICK_HIGH;
    }

    function tickToFee(int24 tick) public pure returns (uint24 fee) {
        require(tick == TICK_LOW || tick == TICK_MEDIUM || tick == TICK_HIGH, "Invalid tick spacing");

        if (tick == TICK_LOW) return FEE_LOW;
        if (tick == TICK_MEDIUM) return FEE_MEDIUM;
        if (tick == TICK_HIGH) return FEE_HIGH;
    }

    uint256 constant PRECISION = 2 ** 96;

    /// @dev Computes the sqrt of the u64x96 fixed point price given the AMM reserves
    /// @dev Taken from gakonst/uniswap-v3-periphery
    /// @param reserve1 The reserve of token1
    /// @param reserve0 The reserve of token0
    function encodePriceSqrt(uint256 reserve1, uint256 reserve0) public pure returns (uint160) {
        return uint160(sqrt((reserve1 * PRECISION * PRECISION) / reserve0));
    }

    /// @dev Fast sqrt, taken from Solmate.
    /// @param x The input value
    function sqrt(uint256 x) public pure returns (uint256 z) {
        assembly {
            // Start off with z at 1.
            z := 1

            // Used below to help find a nearby power of 2.
            let y := x

            // Find the lowest power of 2 that is at least sqrt(x).
            if iszero(lt(y, 0x100000000000000000000000000000000)) {
                y := shr(128, y) // Like dividing by 2 ** 128.
                z := shl(64, z) // Like multiplying by 2 ** 64.
            }
            if iszero(lt(y, 0x10000000000000000)) {
                y := shr(64, y) // Like dividing by 2 ** 64.
                z := shl(32, z) // Like multiplying by 2 ** 32.
            }
            if iszero(lt(y, 0x100000000)) {
                y := shr(32, y) // Like dividing by 2 ** 32.
                z := shl(16, z) // Like multiplying by 2 ** 16.
            }
            if iszero(lt(y, 0x10000)) {
                y := shr(16, y) // Like dividing by 2 ** 16.
                z := shl(8, z) // Like multiplying by 2 ** 8.
            }
            if iszero(lt(y, 0x100)) {
                y := shr(8, y) // Like dividing by 2 ** 8.
                z := shl(4, z) // Like multiplying by 2 ** 4.
            }
            if iszero(lt(y, 0x10)) {
                y := shr(4, y) // Like dividing by 2 ** 4.
                z := shl(2, z) // Like multiplying by 2 ** 2.
            }
            if iszero(lt(y, 0x8)) {
                // Equivalent to 2 ** z.
                z := shl(1, z)
            }

            // Shifting right by 1 is like dividing by 2.
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))

            // Compute a rounded down version of z.
            let zRoundDown := div(x, z)

            // If zRoundDown is smaller, use it.
            if lt(zRoundDown, z) { z := zRoundDown }
        }
    }

    /// @dev Given a particular tickspacing, returns the minimum tick for the pool
    /// @param tickSpacing The tick spacing of the pool
    function getMinTick(int24 tickSpacing) public pure returns (int24) {
        require(tickSpacing == TICK_LOW || tickSpacing == TICK_MEDIUM || tickSpacing == TICK_HIGH, "Invalid tick spacing");
        return (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
    }

    /// @dev Given a particular tickspacing, returns the maximum tick for the pool
    /// @param tickSpacing The tick spacing of the pool
    function getMaxTick(int24 tickSpacing) public pure returns (int24) {
        require(tickSpacing == TICK_LOW || tickSpacing == TICK_MEDIUM || tickSpacing == TICK_HIGH, "Invalid tick spacing");
        return (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
    }

    /// @dev Given addresses of two tokens and a UniswapV3Factory contract and the fee tier, returns the address of the pool
    /// @dev Uses the PoolAddress library
    /// @param tokenA The first token of the pool
    /// @param tokenB The second token of the pool
    /// @param factory The UniswapV3Factory address
    function getComputedPoolAddress(address tokenA, address tokenB, address factory, uint24 fee) public pure returns (address) {
        require(fee == FEE_LOW || fee == FEE_MEDIUM || fee == FEE_HIGH, "Invalid fee tier");

        // Sort tokens alphanumerically
        address token0 = tokenA < tokenB ? tokenA : tokenB;
        address token1 = tokenA < tokenB ? tokenB : tokenA;

        PoolAddress.PoolKey memory key = PoolAddress.PoolKey({token0: token0, token1: token1, fee: FEE_MEDIUM});

        return PoolAddress.computeAddress(factory, key);
    }

    /// @dev Given addresses of two tokens and a UniswapV3Factory contract, returns the address of the pool with FEE_LOW
    /// @param tokenA The first token of the pool
    /// @param tokenB The second token of the pool
    /// @param factory The UniswapV3Factory address
    function getComputedLowFeePoolAddress(address tokenA, address tokenB, address factory) public pure returns (address) {
        return getComputedPoolAddress(tokenA, tokenB, factory, FEE_LOW);
    }

    /// @dev Given addresses of two tokens and a UniswapV3Factory contract, returns the address of the pool with FEE_MEDIUM
    /// @param tokenA The first token of the pool
    /// @param tokenB The second token of the pool
    /// @param factory The UniswapV3Factory address
    function getComputedMediumFeePoolAddress(address tokenA, address tokenB, address factory) public pure returns (address) {
        return getComputedPoolAddress(tokenA, tokenB, factory, FEE_MEDIUM);
    }

    /// @dev Given addresses of two tokens and a UniswapV3Factory contract, returns the address of the pool with FEE_HIGH
    /// @param tokenA The first token of the pool
    /// @param tokenB The second token of the pool
    /// @param factory The UniswapV3Factory address
    function getComputedHighFeePoolAddress(address tokenA, address tokenB, address factory) public pure returns (address) {
        return getComputedPoolAddress(tokenA, tokenB, factory, FEE_HIGH);
    }

    /// @dev Given addresses of tokens in a continuous sequential ordered path, and corresponding fee tiers for each swap
    /// returns the path encoded in the format the UniswapV3Router expects
    /// @dev Be aware that fees should be one element less in length than path!
    /// @dev Taken from gakonst/uniswap-v3-periphery
    /// @param tokens The ordered tokens in the path
    /// @param fees The corresponding fee tiers for each swap
    function encodePath(address[] memory tokens, uint24[] memory fees) public pure returns (bytes memory) {
        require(tokens.length >= 2, "Invalid path length");
        require(fees.length == tokens.length - 1, "Invalid fee length");

        bytes memory res;

        for (uint256 i = 0; i < fees.length; i++) {
            res = abi.encodePacked(res, tokens[i], fees[i]);
        }

        res = abi.encodePacked(res, tokens[tokens.length - 1]);
        return res;
    }
}

abstract contract UniswapV3Utils is Test {
    function deployUniswapV3() public returns (address weth, address factory, address nftManager, address router) {
        weth = address(new MockWeth());
        factory = address(new UniswapV3Factory());
        nftManager = address(new NFTManager(address(factory), address(weth), address(0)));
        router = address(new SwapRouter(address(factory), address(weth)));
    }

    function createPool(address tokenA, uint256 reserveA, address tokenB, uint256 reserveB, address nftManager, uint24 fee)
        public
        returns (address pool)
    {
        require(fee == UniswapV3Math.FEE_LOW || fee == UniswapV3Math.FEE_MEDIUM || fee == UniswapV3Math.FEE_HIGH, "Invalid FEE_TIER");

        (address token0, uint256 reserve0, address token1, uint256 reserve1) =
            (tokenA < tokenB) ? (tokenA, reserveA, tokenB, reserveB) : (tokenB, reserveB, tokenA, reserveA);

        while (reserve0 > 1e10 && reserve1 > 1e10) {
            (reserve0, reserve1) = (reserve0 / 1e10, reserve1 / 1e10);
        }

        uint160 initialPrice = UniswapV3Math.encodePriceSqrt(reserve0, reserve1);

        pool = NFTManager(payable(nftManager)).createAndInitializePoolIfNecessary(token0, token1, fee, initialPrice);
    }

    function mintLiquidity(
        address _tokenA,
        address _tokenB,
        uint256 _spendAmountA,
        uint256 _spendAmountB,
        uint24 _fee,
        address nftManager,
        address recipient
    ) public {
        require(_spendAmountA > 0, "spendAmountA must be > 0");
        require(_fee == UniswapV3Math.FEE_LOW || _fee == UniswapV3Math.FEE_MEDIUM || _fee == UniswapV3Math.FEE_HIGH, "Invalid FEE_TIER");

        (address _token0, address _token1, uint256 _amount0Desired, uint256 _amount1Desired) =
            _tokenA < _tokenB ? (_tokenA, _tokenB, _spendAmountA, _spendAmountB) : (_tokenB, _tokenA, _spendAmountB, _spendAmountA);

        int24 _tick = UniswapV3Math.feeToTick(_fee);

        NFTManager.MintParams memory params = INFTManager.MintParams({
            token0: _token0,
            token1: _token1,
            fee: _fee,
            tickLower: UniswapV3Math.getMinTick(_tick),
            tickUpper: UniswapV3Math.getMaxTick(_tick),
            amount0Desired: _amount0Desired,
            amount1Desired: _amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            recipient: recipient,
            deadline: block.timestamp
        });

        NFTManager(payable(nftManager)).mint(params);
    }

    function swap(address _tokenIn, address _tokenOut, uint256 _amount, address _router, address _recipient, uint24 _fee, bool _exactInput)
        public
        returns (uint256)
    {
        require(_exactInput == true, "Exact output not yet supported.");
        require(_fee == UniswapV3Math.FEE_LOW || _fee == UniswapV3Math.FEE_MEDIUM || _fee == UniswapV3Math.FEE_HIGH, "Invalid FEE_TIER");

        address[] memory tokens = new address[](2);

        tokens[0] = _tokenIn;
        tokens[1] = _tokenOut;

        uint24[] memory fees = new uint24[](1);
        fees[0] = _fee;

        bytes memory _path = UniswapV3Math.encodePath(tokens, fees);

        ISwapRouter.ExactInputParams memory swapParams = ISwapRouter.ExactInputParams({
            path: _path,
            recipient: _recipient,
            deadline: block.timestamp,
            amountIn: _amount,
            amountOutMinimum: 0
        });

        return ISwapRouter(_router).exactInput(swapParams);
    }
}
