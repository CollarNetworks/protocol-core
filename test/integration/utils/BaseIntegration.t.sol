// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import { CollarEngine } from "../../../src/implementations/CollarEngine.sol";
import { CollarVaultManager } from "../../../src/implementations/CollarVaultManager.sol";
import { CollarPool } from "../../../src/implementations/CollarPool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ISwapRouter } from "@uni-v3-periphery/interfaces/ISwapRouter.sol";

/**
 * This contract will hold the base storage variables necessary to run integration tests for the collar protocol
 */
abstract contract CollarBaseIntegrationTestConfig is Test {
    using SafeERC20 for IERC20;

    address user1 = makeAddr("user1"); // the person who will be opening a vault
    address provider = makeAddr("user2"); // the person who will be providing liquidity
    address swapRouterAddress = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    address collateralAssetAddress = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address cashAssetAddress = address(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);
    address uniV3Pool = address(0x2DB87C4831B2fec2E35591221455834193b50D1B);
    address whale = address(0xe7804c37c13166fF0b37F5aE0BB07A3aEbb6e245);
    uint BLOCK_NUMBER_TO_USE = 55_850_000;
    uint COLLATERAL_PRICE_ON_BLOCK = 739_504; // $0.739504 the price for WMatic in USDC on the specified
        // block
        // of polygon mainnet
    uint24 CALL_STRIKE_TICK = 120;
    uint poolDuration = 1 days;
    uint poolLTV = 9000;
    uint tickScaleFactor = 100;
    IERC20 collateralAsset = IERC20(collateralAssetAddress);
    IERC20 cashAsset = IERC20(cashAssetAddress);
    ISwapRouter swapRouter = ISwapRouter(swapRouterAddress);

    CollarEngine engine;
    CollarVaultManager vaultManager;
    CollarPool pool;

    /**
     * This function sets up the configuration for the collar protocol integration tests by setthing the necessary variables based on the forked network and the assets to use and creating the necessary contracts
     * @param _swapRouter the address of the swap router to use
     * @param _cashAsset the address of the cash asset to use
     * @param _collateralAsset the address of the collateral asset to use
     * @param _uniV3Pool the address of the uniswap v3 pool to use
     * @param whaleWallet the address of the whale wallet to use
     * @param blockNumber the block number to use
     * @param priceOnBlock the price of the collateral asset on the block number to use
     * @param callstrikeTickToUse the call strike tick to use
     * @param _poolDuration the pool duration to use
     * @param _poolLTV the pool LTV to use
     */
    function _setupConfig(
        address _swapRouter,
        address _cashAsset,
        address _collateralAsset,
        address _uniV3Pool,
        address whaleWallet,
        uint blockNumber,
        uint priceOnBlock,
        uint24 callstrikeTickToUse,
        uint _poolDuration,
        uint _poolLTV
    ) internal {
        swapRouterAddress = _swapRouter;
        cashAssetAddress = _cashAsset;
        collateralAssetAddress = _collateralAsset;
        collateralAsset = IERC20(collateralAssetAddress);
        cashAsset = IERC20(cashAssetAddress);
        uniV3Pool = _uniV3Pool;
        whale = whaleWallet;
        BLOCK_NUMBER_TO_USE = blockNumber;
        COLLATERAL_PRICE_ON_BLOCK = priceOnBlock;
        CALL_STRIKE_TICK = callstrikeTickToUse;
        engine = new CollarEngine(swapRouterAddress);
        engine.addLTV(_poolLTV);
        pool = new CollarPool(
            address(engine),
            tickScaleFactor,
            cashAssetAddress,
            collateralAssetAddress,
            _poolDuration,
            _poolLTV
        );
        engine.addSupportedCashAsset(cashAssetAddress);
        engine.addSupportedCollateralAsset(collateralAssetAddress);
        engine.addCollarDuration(_poolDuration);
        engine.addLiquidityPool(address(pool));
        poolDuration = _poolDuration;
        poolLTV = _poolLTV;

        vm.label(user1, "USER");
        vm.label(provider, "LIQUIDITY PROVIDER");
        vm.label(address(engine), "ENGINE");
        vm.label(address(pool), "POOL");
        vm.label(swapRouterAddress, "SWAP ROUTER 02");
        vm.label(cashAssetAddress, "Cash asset address");
        vm.label(collateralAssetAddress, "collateral asset address");
        startHoax(user1);
        vaultManager = CollarVaultManager(engine.createVaultManager());

        cashAsset.forceApprove(address(vaultManager), type(uint).max);
        collateralAsset.forceApprove(address(vaultManager), type(uint).max);
    }

    function _addLiquidityToPool(uint amountToProvide) internal {
        startHoax(provider);

        cashAsset.forceApprove(address(pool), type(uint).max);
        collateralAsset.forceApprove(address(pool), type(uint).max);

        pool.addLiquidityToSlot(110, amountToProvide);
        pool.addLiquidityToSlot(111, amountToProvide);
        pool.addLiquidityToSlot(112, amountToProvide);
        pool.addLiquidityToSlot(115, amountToProvide);
        pool.addLiquidityToSlot(120, amountToProvide);
        pool.addLiquidityToSlot(130, amountToProvide);
    }

    function _fundWallets() internal {
        deal(cashAssetAddress, whale, 1_000_000 ether);
        deal(cashAssetAddress, user1, 100_000 ether);
        deal(cashAssetAddress, provider, 100_000 ether);
        deal(collateralAssetAddress, user1, 100_000 ether);
        deal(collateralAssetAddress, provider, 100_000 ether);
        deal(collateralAssetAddress, whale, 1_000_000 ether);
    }

    function _validateSetup(uint amountProvided, uint _duration, uint _poolLTV) internal view {
        assertEq(engine.isValidCollarDuration(_duration), true);
        assertEq(engine.isValidLTV(_poolLTV), true);
        assertEq(engine.isSupportedCashAsset(cashAssetAddress), true);
        assertEq(engine.isSupportedCollateralAsset(collateralAssetAddress), true);
        assertEq(engine.addressToVaultManager(user1), address(vaultManager));
        assertEq(engine.supportedLiquidityPoolsLength(), 1);
        assertEq(engine.isSupportedLiquidityPool(address(pool)), true);
        assertEq(pool.getLiquidityForSlot(110), amountProvided);
        assertEq(pool.getLiquidityForSlot(111), amountProvided);
        assertEq(pool.getLiquidityForSlot(112), amountProvided);
        assertEq(pool.getLiquidityForSlot(115), amountProvided);
        assertEq(pool.getLiquidityForSlot(120), amountProvided);
        assertEq(pool.getLiquidityForSlot(130), amountProvided);
    }
}
