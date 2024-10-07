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
import { CollarOwnedERC20 } from "../test/utils/CollarOwnedERC20.sol";

contract DeployArbitrumSepoliaAssets is Script {
    using SafeERC20 for IERC20;

    // uint constant chainId = 421_614; // Arbitrum Sepolia
    address constant uniswapV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984; // Arbitrum Sepolia UniswapV3Factory

    IV3SwapRouter constant SWAP_ROUTER = IV3SwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    uint24 constant FEE_TIER = 3000;
    uint constant INITIAL_MINT_AMOUNT = 1_000_000_000 ether; // 1 billion tokens

    struct TickRange {
        int24 currentTick;
        int24 lowerTick;
        int24 upperTick;
    }

    INonfungiblePositionManager constant POSITION_MANAGER =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

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
        // require(block.chainid == chainId, "Wrong chain");

        uint deployerPrivateKey = vm.envUint("PRIVKEY_DEV_DEPLOYER");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        initializeAssets();
        initializeAssetPairs();
        deployAssets(deployer);
        createAndInitializePools(deployer);

        vm.stopBroadcast();

        logDeployedAssets();
    }

    function initializeAssets() internal {
        // assets.push(Asset("coll", 18));
        // assets.push(Asset("cash", 6));
        assets.push(Asset("USDC", 6));
        // assets.push(Asset("USDT", 6));
        assets.push(Asset("wETH", 18));
        assets.push(Asset("wBTC", 8));
        // assets.push(Asset("wPOL", 18));
        // assets.push(Asset("wstETH", 18));
        // assets.push(Asset("weETH", 18));
        // assets.push(Asset("cbBTC", 8));
        // assets.push(Asset("rETH", 18));
        // assets.push(Asset("cbETH", 18));
    }

    function initializeAssetPairs() internal {
        // assetPairs.push(AssetPair("coll", "cash", 10_311_236_408_134_789_464_653, 8_946_112_041_115));
        assetPairs.push(AssetPair("wETH", "USDC", 1 ether, 2462e6));
        // assetPairs.push(AssetPair("wETH", "USDT", 11_312_811_541_194_607_057_025, 9_192_731_529_757));
        assetPairs.push(AssetPair("wBTC", "USDC", 1e8, 61_000e6));
        // assetPairs.push(AssetPair("wBTC", "USDT", 328e8, 20_025_613_600_000));
        // assetPairs.push(AssetPair("wPOL", "USDC", 1_315_000 ether, 20_027_450_000_000));
        // assetPairs.push(AssetPair("wPOL", "USDT", 1_315_000 ether, 20_027_450_000_000));
        // assetPairs.push(AssetPair("wstETH", "USDC", 6950 ether, 20_055_545_500_000));
        // assetPairs.push(AssetPair("wstETH", "USDT", 6950 ether, 20_055_545_500_000));
        // assetPairs.push(AssetPair("wstETH", "wETH", 17_000 ether, 20_015.8 ether));
        // assetPairs.push(AssetPair("weETH", "wETH", 19_080 ether, 20_000 ether));
        // assetPairs.push(AssetPair("rETH", "USDC", 5900 ether, 20_014_452_000_000));
        // assetPairs.push(AssetPair("rETH", "USDT", 5900 ether, 20_014_452_000_000));
    }

    function deployAssets(address deployer) internal {
        for (uint i = 0; i < assets.length; i++) {
            Asset memory asset = assets[i];
            if (deployedAssets[asset.symbol] == address(0)) {
                CollarOwnedERC20 newAsset =
                    new CollarOwnedERC20(deployer, asset.symbol, asset.symbol, asset.decimals);
                newAsset.mint(deployer, INITIAL_MINT_AMOUNT);
                deployedAssets[asset.symbol] = address(newAsset);
                console.log("Deployed", asset.symbol, "at", address(newAsset));
            }
        }
    }

    function createAndInitializePools(address deployer) internal {
        for (uint i = 0; i < assetPairs.length; i++) {
            AssetPair memory pair = assetPairs[i];
            address cashAsset = deployedAssets[pair.cashSymbol];
            address collateralAsset = deployedAssets[pair.collateralSymbol];

            require(cashAsset != address(0) && collateralAsset != address(0), "Assets not deployed");

            address poolAddress = createPool(cashAsset, collateralAsset);
            initializePool(poolAddress, pair, deployer);

            deployedPools[pair.collateralSymbol][pair.cashSymbol] = poolAddress;

            uint poolCashAssetBalance = IERC20(cashAsset).balanceOf(poolAddress);
            uint poolCollateralAssetBalance = IERC20(collateralAsset).balanceOf(poolAddress);
            (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(poolAddress).slot0();
            console.log("pool cash balance ", poolCashAssetBalance);
            console.log("pool collateral balance ", poolCollateralAssetBalance);
            console.log("pool sqrtPriceX96 ", sqrtPriceX96);
            verifySwapAmount(pair, deployer);
        }
    }

    function createPool(address token0, address token1) internal returns (address) {
        return IUniswapV3Factory(uniswapV3FactoryAddress).createPool(token0, token1, FEE_TIER);
    }

    function initializePool(address poolAddress, AssetPair memory pair, address deployer) internal {
        CollarOwnedERC20 cashAsset = CollarOwnedERC20(deployedAssets[pair.cashSymbol]);
        CollarOwnedERC20 collateralAsset = CollarOwnedERC20(deployedAssets[pair.collateralSymbol]);

        cashAsset.mint(deployer, pair.amountCashDesired);
        collateralAsset.mint(deployer, pair.amountCollDesired);

        // Approve tokens
        collateralAsset.approve(address(POSITION_MANAGER), type(uint).max);
        cashAsset.approve(address(POSITION_MANAGER), type(uint).max);
        address token0 = IUniswapV3Pool(poolAddress).token0();
        address token1 = IUniswapV3Pool(poolAddress).token1();
        (uint amount0Desired, uint amount1Desired) = token0 == address(collateralAsset)
            ? (pair.amountCollDesired, pair.amountCashDesired)
            : (pair.amountCashDesired, pair.amountCollDesired);
        // uint160 sqrtPriceX96 = 79_228_162_514_264_337_593_543_950_336; // 1:1 price
        uint160 sqrtPriceX96 = getSqrtPriceX96ByAmounts(amount0Desired, amount1Desired);
        IUniswapV3Pool(poolAddress).initialize(sqrtPriceX96);
        (, int24 currentTick,,,,,) = IUniswapV3Pool(poolAddress).slot0();
        int24 tickSpacing = IUniswapV3Pool(poolAddress).tickSpacing();
        console.log("current tick");
        console.logInt(currentTick);
        // doesnt seem like changing this multiplier (50) does anything regarding price range
        int24 tickLower = (currentTick - tickSpacing * 50) / tickSpacing * tickSpacing;
        int24 tickUpper = (currentTick + tickSpacing * 50) / tickSpacing * tickSpacing;
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: FEE_TIER,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            recipient: deployer,
            deadline: block.timestamp + 15 minutes
        });

        (, uint128 liquidity, uint amount0, uint amount1) = POSITION_MANAGER.mint(params);
        // Add more liquidity
        // for (uint i = 0; i < 1; i++) {
        //     params.amount0Desired = amount0Desired * 10;
        //     params.amount1Desired = amount1Desired * 10;

        //     (, liquidity, amount0, amount1) = POSITION_MANAGER.mint(params);

        //     console.log("Additional liquidity added (iteration", i + 1, "):");
        //     console.log("Liquidity:", liquidity);
        //     console.log("Amount0:", amount0);
        //     console.log("Amount1:", amount1);
        // }
        (sqrtPriceX96, currentTick,,,,,) = IUniswapV3Pool(poolAddress).slot0();
        console.log("current tick after mint");
        console.logInt(currentTick);
        console.log("sqrtPriceX96 after mint", sqrtPriceX96);
        console.log("tick lower ");
        console.logInt(tickLower);
        console.log("tick upper ");
        console.logInt(tickUpper);
        console.log("is cash token0 ", token0 == address(cashAsset));
        console.log("amount0 desired ", amount0Desired);
        console.log("amount1 desired ", amount1Desired);
        console.log("Minted liquidity", liquidity);
        console.log("Minted amount0", amount0);
        console.log("Minted amount1", amount1);
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
            console.log(deployedAssets[pair.collateralSymbol], ", ", deployedAssets[pair.cashSymbol]);
        }
    }

    function getSqrtPriceX96ByAmounts(uint amount0, uint amount1) public pure returns (uint160) {
        uint price = amount1 * (1e18) / amount0;
        return encodePriceToSqrtPriceX96(price);
    }

    function encodePriceToSqrtPriceX96(uint price) private pure returns (uint160) {
        return uint160(Math.sqrt((price << 192) / 1e18));
    }

    function verifySwapAmount(AssetPair memory pair, address deployer) internal {
        CollarOwnedERC20 cashAsset = CollarOwnedERC20(deployedAssets[pair.cashSymbol]);
        CollarOwnedERC20 collateralAsset = CollarOwnedERC20(deployedAssets[pair.collateralSymbol]);
        uint amountIn = 10 ** collateralAsset.decimals();
        // Approve the router to spend tokens
        collateralAsset.approve(address(SWAP_ROUTER), amountIn);

        // Prepare the parameters for the swap
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: address(collateralAsset),
            tokenOut: address(cashAsset),
            fee: FEE_TIER,
            recipient: deployer,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        // Execute the swap
        uint amountOut = SWAP_ROUTER.exactInputSingle(params);
        console.log("amount in ", amountIn);
        console.log("Amount out", amountOut);
    }
}
