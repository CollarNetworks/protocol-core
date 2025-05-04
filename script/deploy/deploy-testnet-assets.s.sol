// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import { CollarOwnedERC20 } from "../../test/utils/CollarOwnedERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Const } from "../utils/Const.sol";

abstract contract AssetDeployer is Script {
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
        string underlyingSymbol;
        string cashSymbol;
        uint amountUnderlyingDesired;
        uint amountCashDesired;
        uint priceRatio; // amount of cash for 1 underlying
    }

    Asset[] public assets;
    AssetPair[] public assetPairs;
    mapping(string => address) public deployedAssets;
    mapping(string => mapping(string => address)) public deployedPools;

    function run() external {
        vm.startBroadcast(msg.sender);

        setUp();

        deployAssets(msg.sender);

        createAndInitializePools(msg.sender);

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

            // set cash asset if deploying it. Must be first asset
            if (deployingCashAsset && i == 0) {
                cashAsset = address(newAsset);
            }
        }
    }

    function createAndInitializePools(address deployerAcc) internal {
        for (uint i = 0; i < assetPairs.length; i++) {
            AssetPair memory pair = assetPairs[i];
            address underlying = deployedAssets[pair.underlyingSymbol];

            require(cashAsset != address(0) && underlying != address(0), "Assets not deployed");

            (address token0, address token1) =
                (cashAsset > underlying) ? (underlying, cashAsset) : (cashAsset, underlying);
            address poolAddress = IUniswapV3Factory(uniFactory).createPool(token0, token1, feeTier);
            console.log("Created pool for underlying ", underlying);
            console.log("Created pool at", poolAddress);
            initializePool(poolAddress, pair, deployerAcc);

            deployedPools[pair.underlyingSymbol][pair.cashSymbol] = poolAddress;

            console.log("pool cash balance ", IERC20(cashAsset).balanceOf(poolAddress));
            console.log("pool collateral balance ", IERC20(underlying).balanceOf(poolAddress));
            (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(poolAddress).slot0();
            console.log("pool sqrtPriceX96 ", sqrtPriceX96);
        }
    }

    /**
     * @notice Calculates sqrt(price) * 2^96 for Uniswap V3 price format
     * @dev Uses formula: sqrtPriceX96 = sqrt(amount1/amount0) * 2^96
     * Shifts by 192 (2*96) before sqrt to maintain precision in Q64.96 format
     *  sqrt((amount1/amount0) * 2^192) = sqrt(price) * 2^96
     *  https://blog.uniswap.org/uniswap-v3-math-primer
     */
    function getSqrtPriceX96ForPriceRatio(uint amount0, uint amount1) internal pure returns (uint160) {
        return uint160(Math.sqrt((amount1 << 192) / amount0));
    }

    // stack too deep
    function _mintPosition(
        address poolAddress,
        address token0,
        address token1,
        uint amount0Desired,
        uint amount1Desired,
        address deployer
    ) internal {
        (, int24 currentTick,,,,,) = IUniswapV3Pool(poolAddress).slot0();
        int24 tickSpacing = IUniswapV3Pool(poolAddress).tickSpacing();

        // provide in 10 bins (initialiazed ticks) up and down from the current tick
        // `/ tickSpacing * tickSpacing` aligns to the allowed ticks for this fee tier
        int24 tickLower = (currentTick - tickSpacing * 10) / tickSpacing * tickSpacing;
        int24 tickUpper = (currentTick + tickSpacing * 10) / tickSpacing * tickSpacing;

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

        // Logging
        console.log("Minted liquidity", liquidity);
        console.log("Minted amount0", amount0);
        console.log("Minted amount1", amount1);

        (uint160 sqrtPriceX96, int24 finalTick,,,,,) = IUniswapV3Pool(poolAddress).slot0();
        console.log("current tick after mint");
        console.logInt(finalTick);
        console.log("sqrtPriceX96 after mint", sqrtPriceX96);
    }

    function initializePool(address poolAddress, AssetPair memory pair, address deployer) internal {
        // Initial minting and approvals
        CollarOwnedERC20 underlying = CollarOwnedERC20(deployedAssets[pair.underlyingSymbol]);
        underlying.mint(deployer, pair.amountUnderlyingDesired);
        underlying.approve(uniPosMan, type(uint).max);
        CollarOwnedERC20(cashAsset).approve(uniPosMan, type(uint).max);

        // Get token ordering and initialize pool
        address token0 = IUniswapV3Pool(poolAddress).token0();
        address token1 = IUniswapV3Pool(poolAddress).token1();

        (uint baseAmount0, uint baseAmount1) = token0 == address(underlying)
            ? (10 ** IERC20Metadata(token0).decimals(), pair.priceRatio)
            : (pair.priceRatio, 10 ** IERC20Metadata(token1).decimals());

        uint160 sqrtPriceX96 = getSqrtPriceX96ForPriceRatio(baseAmount0, baseAmount1);
        IUniswapV3Pool(poolAddress).initialize(sqrtPriceX96);

        (uint amount0Desired, uint amount1Desired) = token0 == address(deployedAssets[pair.underlyingSymbol])
            ? (pair.amountUnderlyingDesired, pair.amountCashDesired)
            : (pair.amountCashDesired, pair.amountUnderlyingDesired);

        // Create and execute mint params
        _mintPosition(poolAddress, token0, token1, amount0Desired, amount1Desired, deployer);
    }

    function logDeployedAssets() internal view {
        console.log("\n--- Deployed Assets ---");
        for (uint i = 0; i < assets.length; i++) {
            console.log(assets[i].symbol, ":", deployedAssets[assets[i].symbol]);
        }

        console.log("\n--- Asset Pair Addresses (for initialization) ---");
        for (uint i = 0; i < assetPairs.length; i++) {
            AssetPair memory pair = assetPairs[i];
            console.log("AssetPair", pair.underlyingSymbol, ",", pair.cashSymbol);
            console.log(deployedAssets[pair.underlyingSymbol], ", ", cashAsset);
        }
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

        uint wbtcUnits = 10_000;
        // For WBTC/USDC: 100000 USDC per 1 WBTC
        uint wbtcAmount = wbtcUnits * 1e8; // 10k WBTC
        uint wbtcUsdcRatio = 100_000 * 1e6;
        uint wbtcUsdcAmount = wbtcUnits * wbtcUsdcRatio; // 10k * 100k  USDC

        assetPairs.push(AssetPair("wBTC", "tUSDC", wbtcAmount, wbtcUsdcAmount, wbtcUsdcRatio));
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

        // USDC (6 decimals), WETH (18 decimals), WBTC (8 decimals)
        assets.push(Asset("tUSDC", 6));
        assets.push(Asset("tWBTC", 8));
        assets.push(Asset("tWETH", 18));

        uint wbtcUnits = 10_000;
        // For WBTC/USDC: 100000 USDC per 1 WBTC
        uint wbtcAmount = wbtcUnits * 1e8; // 10k WBTC
        uint wbtcUsdcRatio = 100_000 * 1e6;
        uint wbtcUsdcAmount = wbtcUnits * wbtcUsdcRatio; // 10k * 100k  USDC

        uint wethUnits = 1e6;
        // For WETH/USDC: 3500 USDC per 1 WETH
        uint wethAmount = wethUnits * 1e18; // 1M WETH
        uint wethUsdcRatio = 3500 * 1e6;
        uint wethUsdcAmount = wethUnits * wethUsdcRatio; // 1M * 3500 USDC

        assetPairs.push(AssetPair("tWBTC", "tUSDC", wbtcAmount, wbtcUsdcAmount, wbtcUsdcRatio));
        assetPairs.push(AssetPair("tWETH", "tUSDC", wethAmount, wethUsdcAmount, wethUsdcRatio));
    }
}
