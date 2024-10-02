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
import { CollarOwnedERC20 } from "../test/utils/CollarOwnedERC20.sol";

contract DeployArbitrumSepoliaAssets is Script {
    using SafeERC20 for IERC20;

    uint constant chainId = 421_614; // Arbitrum Sepolia
    address constant uniswapV3FactoryAddress = 0x248AB79Bbb9bC29bB72f7Cd42F17e054Fc40188e; // Arbitrum Sepolia UniswapV3Factory
    uint24 constant FEE_TIER = 3000;
    uint constant INITIAL_MINT_AMOUNT = 1_000_000_000 ether; // 1 billion tokens

    INonfungiblePositionManager constant POSITION_MANAGER =
        INonfungiblePositionManager(0x6b2937Bde17889EDCf8fbD8dE31C3C2a70Bc4d65);

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
        require(block.chainid == chainId, "Wrong chain");

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
        assets.push(Asset("USDT", 6));
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
        assetPairs.push(AssetPair("wETH", "USDC", 8200 ether, 20_098_692_000_000));
        assetPairs.push(AssetPair("wETH", "USDT", 8200 ether, 20_088_606_000_000));
        assetPairs.push(AssetPair("wBTC", "USDC", 328 * 1e8, 20_025_613_600_000));
        assetPairs.push(AssetPair("wBTC", "USDT", 328 * 1e8, 20_025_613_600_000));
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
        }
    }

    function createPool(address token0, address token1) internal returns (address) {
        return IUniswapV3Factory(uniswapV3FactoryAddress).createPool(token0, token1, FEE_TIER);
    }

    function initializePool(address poolAddress, AssetPair memory pair, address deployer) internal {
        CollarOwnedERC20 cashAsset = CollarOwnedERC20(deployedAssets[pair.cashSymbol]);
        CollarOwnedERC20 collateralAsset = CollarOwnedERC20(deployedAssets[pair.collateralSymbol]);

        cashAsset.mint(deployer, pair.amountCashDesired * 10);
        collateralAsset.mint(deployer, pair.amountCollDesired * 10);

        // Approve tokens
        collateralAsset.approve(address(POSITION_MANAGER), type(uint).max);
        cashAsset.approve(address(POSITION_MANAGER), type(uint).max);

        address token0 = IUniswapV3Pool(poolAddress).token0();
        address token1 = IUniswapV3Pool(poolAddress).token1();
        uint amount0Desired = pair.amountCashDesired;
        uint amount1Desired = pair.amountCollDesired;
        bool isToken0Cash = token0 == address(collateralAsset);
        uint160 sqrtPriceX96 =
            calculateSqrtPriceX96(pair.amountCashDesired, pair.amountCollDesired, isToken0Cash);
        if (!isToken0Cash) {
            amount0Desired = pair.amountCollDesired;
            amount1Desired = pair.amountCashDesired;
        }
        IUniswapV3Pool(poolAddress).initialize(sqrtPriceX96);

        (, int24 currentTick,,,,,) = IUniswapV3Pool(poolAddress).slot0();
        int24 tickSpacing = IUniswapV3Pool(poolAddress).tickSpacing();
        int24 tickLower = (currentTick - tickSpacing * 10) / tickSpacing * tickSpacing;
        int24 tickUpper = (currentTick + tickSpacing * 10) / tickSpacing * tickSpacing;

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

        POSITION_MANAGER.mint(params);
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

    function calculateSqrtPriceX96(uint amountCash, uint amountColl, bool isToken0Cash)
        public
        pure
        returns (uint160)
    {
        uint price = isToken0Cash
            ? (amountCash * 1e18 / amountColl) // If cash is token0, price = cash/coll
            : (amountColl * 1e18 / amountCash); // If coll is token0, price = coll/cash
        uint sqrtPrice = Math.sqrt(price * 1e18);
        return uint160(sqrtPrice * 2 ** 96 / 1e9);
    }
}
