// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { CollarOwnedERC20 } from "../../test/utils/CollarOwnedERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Const } from "../utils/Const.sol";

abstract contract AssetDeployer is Script {
    using SafeERC20 for IERC20;

    uint constant INITIAL_MINT_AMOUNT = 10_000_000_000 ether; // 10 billion tokens

    uint24 feeTier;
    bool deployingCashAsset;
    address cashAsset;
    address uniRouter;
    address uniFactory;
    address uniPosMan;

    struct Asset {
        string symbol;
        uint8 decimals;
    }

    struct AssetPair {
        string collateralSymbol;
        string cashSymbol;
        uint amountCollDesired;
        uint amountCashDesired;
    }

    Asset[] public assets;
    AssetPair[] public assetPairs;
    mapping(string => address) public deployedAssets;
    mapping(string => mapping(string => address)) public deployedPools;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVKEY_DEV_DEPLOYER");
        address deployerAcc = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        setUp();

        deployAssets(deployerAcc);

        createAndInitializePools(deployerAcc);

        vm.stopBroadcast();

        logDeployedAssets();
    }

    function setUp() internal virtual;

    function deployAssets(address deployerAcc) internal {
        for (uint i = 0; i < assets.length; i++) {
            Asset memory asset = assets[i];
            require(deployedAssets[asset.symbol] == address(0), "already deployed");

            CollarOwnedERC20 newAsset =
                new CollarOwnedERC20(deployerAcc, asset.symbol, asset.symbol, asset.decimals);
            newAsset.mint(deployerAcc, INITIAL_MINT_AMOUNT);
            deployedAssets[asset.symbol] = address(newAsset);
            console.log("Deployed", asset.symbol, "at", address(newAsset));

            // set cash asset if deploying it. Must be first asset
            if (deployingCashAsset && i == 0) {
                cashAsset = address(newAsset);
            }
        }
    }

    function createAndInitializePools(address deployerAcc) internal {
        for (uint i = 0; i < assetPairs.length; i++) {
            AssetPair memory pair = assetPairs[i];
            address underlying = deployedAssets[pair.collateralSymbol];

            require(cashAsset != address(0) && underlying != address(0), "Assets not deployed");

            address poolAddress = createPool(cashAsset, underlying);
            console.log("Created pool at", poolAddress);
            initializePool(poolAddress, pair, deployerAcc);

            deployedPools[pair.collateralSymbol][pair.cashSymbol] = poolAddress;

            uint poolCashAssetBalance = IERC20(cashAsset).balanceOf(poolAddress);
            uint poolCollateralAssetBalance = IERC20(underlying).balanceOf(poolAddress);
            (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(poolAddress).slot0();
            console.log("pool cash balance ", poolCashAssetBalance);
            console.log("pool collateral balance ", poolCollateralAssetBalance);
            console.log("pool sqrtPriceX96 ", sqrtPriceX96);

            // make a small swap to check amounts
            CollarOwnedERC20 underlyingToken = CollarOwnedERC20(deployedAssets[pair.collateralSymbol]);
            uint amountIn = 10 ** underlyingToken.decimals();
            // Approve the router to spend tokens
            underlyingToken.approve(uniRouter, amountIn);

            // Prepare the parameters for the swap
            IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
                tokenIn: underlying,
                tokenOut: cashAsset,
                fee: feeTier,
                recipient: deployerAcc,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            // Execute the swap
            uint amountOut = IV3SwapRouter(uniRouter).exactInputSingle(params);
            console.log("amount in ", amountIn);
            console.log("Amount out", amountOut);
        }
    }

    function sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address token0, address token1)
    {
        if (tokenA > tokenB) {
            (token0, token1) = (tokenB, tokenA);
        } else {
            (token0, token1) = (tokenA, tokenB);
        }
        require(token0 != address(0), "ZERO_ADDRESS");
    }

    function createPool(address tokenA, address tokenB) internal returns (address) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        return IUniswapV3Factory(uniFactory).createPool(token0, token1, feeTier);
    }

    function initializePool(address poolAddress, AssetPair memory pair, address deployer) internal {
        CollarOwnedERC20 collateralAsset = CollarOwnedERC20(deployedAssets[pair.collateralSymbol]);

        // cashAsset.mint(deployer, pair.amountCashDesired);
        collateralAsset.mint(deployer, pair.amountCollDesired);

        // Approve tokens
        collateralAsset.approve(uniPosMan, type(uint).max);
        CollarOwnedERC20(cashAsset).approve(uniPosMan, type(uint).max);
        address token0 = IUniswapV3Pool(poolAddress).token0();
        address token1 = IUniswapV3Pool(poolAddress).token1();
        (uint amount0Desired, uint amount1Desired) = token0 == address(collateralAsset)
            ? (pair.amountCollDesired, pair.amountCashDesired)
            : (pair.amountCashDesired, pair.amountCollDesired);
        console.log("is cash token0 ", token0 == cashAsset);
        console.log("amount0 desired ", amount0Desired);
        console.log("amount1 desired ", amount1Desired);

        // uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336; // 1:1 price
        uint160 sqrtPriceX96 = getSqrtPriceX96ByAmounts(token0, token1, amount0Desired, amount1Desired);
        IUniswapV3Pool(poolAddress).initialize(sqrtPriceX96);
        (, int24 currentTick,,,,,) = IUniswapV3Pool(poolAddress).slot0();
        int24 tickSpacing = IUniswapV3Pool(poolAddress).tickSpacing();
        console.log("current tick");
        console.logInt(currentTick);

        {
            // doesnt seem like changing this multiplier (50) does anything regarding price range
            int24 tickLower = (currentTick - tickSpacing * 50) / tickSpacing * tickSpacing;
            int24 tickUpper = (currentTick + tickSpacing * 50) / tickSpacing * tickSpacing;
            console.log("tick lower ");
            console.logInt(tickLower);
            console.log("tick upper ");
            console.logInt(tickUpper);
            INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: feeTier,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: deployer,
                deadline: block.timestamp + 15 minutes
            });

            (, uint128 liquidity, uint amount0, uint amount1) =
                INonfungiblePositionManager(uniPosMan).mint(params);
            console.log("Minted liquidity", liquidity);
            console.log("Minted amount0", amount0);
            console.log("Minted amount1", amount1);
        }
        // Add more liquidity
        // for (uint i = 0; i < 1; i++) {
        //     params.amount0Desired = amount0Desired * 10;
        //     params.amount1Desired = amount1Desired * 10;

        //     (, liquidity, amount0, amount1) = INonfungiblePositionManager(uniPosMan).mint(params);

        //     console.log("Additional liquidity added (iteration", i + 1, "):");
        //     console.log("Liquidity:", liquidity);
        //     console.log("Amount0:", amount0);
        //     console.log("Amount1:", amount1);
        // }
        (sqrtPriceX96, currentTick,,,,,) = IUniswapV3Pool(poolAddress).slot0();
        console.log("current tick after mint");
        console.logInt(currentTick);
        console.log("sqrtPriceX96 after mint", sqrtPriceX96);
    }

    function logDeployedAssets() internal view {
        console.log("\n--- Deployed Assets ---");
        for (uint i = 0; i < assets.length; i++) {
            console.log(assets[i].symbol, ":", deployedAssets[assets[i].symbol]);
        }

        console.log("\n--- Asset Pair Addresses (for initialization) ---");
        for (uint i = 0; i < assetPairs.length; i++) {
            AssetPair memory pair = assetPairs[i];
            console.log("AssetPair", pair.collateralSymbol, ",", pair.cashSymbol);
            console.log(deployedAssets[pair.collateralSymbol], ", ", cashAsset);
        }
    }

    function getSqrtPriceX96ByAmounts(address token0, address token1, uint amount0, uint amount1)
        public
        view
        returns (uint160)
    {
        uint8 decimals0 = IERC20Metadata(token0).decimals();
        uint8 decimals1 = IERC20Metadata(token1).decimals();

        // Normalize both amounts to 18 decimals for precision consistency
        uint normalizedAmount0 = amount0 * (10 ** (18 - decimals0));
        uint normalizedAmount1 = amount1 * (10 ** (18 - decimals1));

        // Calculate price ratio as token1/token0 in 18 decimals
        uint priceRatio = (normalizedAmount1 * 1e18) / normalizedAmount0;

        return encodePriceToSqrtPriceX96(priceRatio);
    }

    function encodePriceToSqrtPriceX96(uint price) private pure returns (uint160) {
        return uint160(Math.sqrt((price << 192) / 1e16)); // this value to be adjusted depending on the pair and arbitrary testing
    }
}

contract DeployArbitrumSepoliaAssets is AssetDeployer {
    function setUp() internal virtual override {
        // check chain
        require(block.chainid == Const.ArbiSep_chainId, "Wrong chain");

        // set params
        feeTier = 500;
        deployingCashAsset = false;
        cashAsset = Const.ArbiSep_tUSDC;
        uniRouter = Const.ArbiSep_UniRouter;
        uniFactory = Const.ArbiSep_UniFactory;
        uniPosMan = Const.ArbiSep_UniPosMan;

        // assets
        assets.push(Asset("wBTC", 8));

        // pairs
        assetPairs.push(AssetPair("wBTC", "USDC", 1e6 * 1e8, 2e7 * 61_000 * 1e6));
    }
}

contract DeployOPBaseSepoliaAssets_WithCashAsset is AssetDeployer {
    function setUp() internal virtual override {
        // check chain
        require(block.chainid == Const.OPBaseSep_chainId, "Wrong chain");

        // set params
        feeTier = 500;
        deployingCashAsset = true;
        cashAsset = address(0); // should be deployed by this script
        uniRouter = Const.OPBaseSep_UniRouter;
        uniFactory = Const.OPBaseSep_UniFactory;
        uniPosMan = Const.OPBaseSep_UniPosMan;

        // assets, first asset must be cash asset if deploying it
        assets.push(Asset("tUSDC", 8));
        assets.push(Asset("tWETH", 8));
        assets.push(Asset("tWBTC", 8));

        // pairs
        assetPairs.push(AssetPair("tWBTC", "tUSDC", 1e6 * 1e8, 2e7 * 61_000 * 1e6));
        assetPairs.push(AssetPair("tWETH", "tUSDC", 1e6 * 1e8, 2e7 * 61_000 * 1e6));
    }
}
