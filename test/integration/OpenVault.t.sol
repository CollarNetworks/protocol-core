// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { CollarEngine } from "../../src/implementations/CollarEngine.sol";
import { CollarVaultManager } from "../../src/implementations/CollarVaultManager.sol";
import { CollarPool } from "../../src/implementations/CollarPool.sol";
import { ICollarVaultState } from "../../src/interfaces/ICollarVaultState.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISwapRouter } from "@uni-v3-periphery/interfaces/ISwapRouter.sol";

// Polygon Addresses for UniswapV3

// QuoterV2 - - - - - - - - - - - - 0x61fFE014bA17989E743c5F6cB21bF9697530B21e
// SwapRouter02 - - - - - - - - - - 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45
// UniversalRouter  - - - - - - - - 0xec7BE89e9d109e7e3Fec59c222CF297125FEFda2
// NonFungiblePositionManager - - - 0xC36442b4a4522E871399CD717aBDD847Ab11FE88
// TickLens - - - - - - - - - - - - 0xbfd8137f7d1516D3ea5cA83523914859ec47F573
// WETH - - - - - - - - - - - - - - 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619
// USDC - - - - - - - - - - - - - - 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359

contract CollarOpenVaultIntegrationTest is Test {
    address user = makeAddr("user1");       // the person who will be opening a vault
    address provider = makeAddr("user2");   // the person who will be providing liquidity
    address swapRouterAddress = address(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
    address WETHAddress = address(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
    address USDCAddress = address(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);

    IERC20 WETH = IERC20(WETHAddress);
    IERC20 USDC = IERC20(USDCAddress);

    ISwapRouter swapRouter = ISwapRouter(swapRouterAddress);

    CollarEngine engine;
    CollarVaultManager vaultManager;
    CollarPool pool;

    /* We set up the test environment as follows:

    1. We fork Polygon and activate the fork
    2. We deploy the CollarEngine with the dex set to SwapRouter02 from Uniswap on the polygon fork
    3. We add the LTV of 90% to the engine, as well as the cash and collateral assets & duration
    4. We deploy a CollarPool with the following parameters:
        - engine: address of the CollarEngine
        - tickScaleFactor: 100 (1 tick = 1%)
        - cashAsset: USDC
        - collateralAsset: WETH
        - duration: 1 day
        - ltv: 9000 (90%)
    5. We add the pool to the engine
    6. We give the user USDC and WETH, as well as the liquidity provider
    7. WE label existing addresses for better test output
    8. We deploy a vault manager for the user
    9. We approve the vault manager to spend the user's USDC and WETH
    10. We approve the pool to spend the liquidity provider's USDC and WETH
    11. We add liquidity to the pool in ticks 110 through 115 (as the liquidity provider)

    */

    function setUp() public {
        string memory forkRPC = vm.envString("POLYGON_MAINNET_RPC");
        vm.createSelectFork(forkRPC, 55000000);
        assertEq(block.number, 55000000);

        engine = new CollarEngine(swapRouterAddress);
        engine.addLTV(9000);

        pool = new CollarPool(address(engine), 100, USDCAddress, WETHAddress, 1 days, 9000);
    
        engine.addSupportedCashAsset(USDCAddress);
        engine.addSupportedCollateralAsset(WETHAddress);
        engine.addCollarDuration(1 days);
        engine.addLiquidityPool(address(pool));

        vm.label(user, "USER");
        vm.label(provider, "LIQUIDITY PROVIDER");
        vm.label(address(engine), "ENGINE");
        vm.label(address(pool), "POOL");
        vm.label(swapRouterAddress, "SWAP ROUTER 02");
        vm.label(USDCAddress, "USDC");
        vm.label(WETHAddress, "WETH");

        deal(USDCAddress, user, 100_000 ether);
        deal(WETHAddress, user, 100_000 ether);
        deal(USDCAddress, provider, 100_000 ether);
        deal(WETHAddress, provider, 100_000 ether);

        startHoax(user);

        vaultManager = CollarVaultManager(engine.createVaultManager());
        USDC.approve(address(vaultManager), 100_000 ether);
        WETH.approve(address(vaultManager), 100_000 ether);

        startHoax(provider);

        USDC.approve(address(pool), 100_000 ether);
        WETH.approve(address(pool), 100_000 ether);

        pool.addLiquidityToSlot(110, 10_000 ether);
        pool.addLiquidityToSlot(111, 11_000 ether);
        pool.addLiquidityToSlot(112, 12_000 ether);
        pool.addLiquidityToSlot(113, 13_000 ether);
        pool.addLiquidityToSlot(114, 12_000 ether);
        pool.addLiquidityToSlot(115, 11_000 ether);

        vm.stopPrank();

        assertEq(engine.isValidCollarDuration(1 days), true);        
        assertEq(engine.isValidLTV(9000), true);
        assertEq(engine.isSupportedCashAsset(USDCAddress), true);
        assertEq(engine.isSupportedCollateralAsset(WETHAddress), true);
        assertEq(engine.addressToVaultManager(user), address(vaultManager));
        assertEq(engine.supportedLiquidityPoolsLength(), 1);
        assertEq(engine.isSupportedLiquidityPool(address(pool)), true);
    
        assertEq(pool.getLiquidityForSlot(110), 10_000 ether);
        assertEq(pool.getLiquidityForSlot(111), 11_000 ether);
        assertEq(pool.getLiquidityForSlot(112), 12_000 ether);
        assertEq(pool.getLiquidityForSlot(113), 13_000 ether);
        assertEq(pool.getLiquidityForSlot(114), 12_000 ether);
        assertEq(pool.getLiquidityForSlot(115), 11_000 ether);
    }

    function test_openVault() public {
        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: WETHAddress,
            collateralAmount: 1 ether,
            cashAsset: USDCAddress,
            cashAmount: 100e6
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ 
            duration: 1 days, 
            ltv: 9000 
        });

        ICollarVaultState.LiquidityOpts memory liquidityOpts = ICollarVaultState.LiquidityOpts({ 
            liquidityPool: address(pool), 
            putStrikeTick: 90, 
            callStrikeTick: 110 
        });
        
        startHoax(user);

        vaultManager.openVault(assets, collarOpts, liquidityOpts);
        bytes32 uuid = vaultManager.getVaultUUID(0);
        bytes memory rawVault = vaultManager.vaultInfo(uuid);
        ICollarVaultState.Vault memory vault = abi.decode(rawVault, (ICollarVaultState.Vault));

        // check basic vault info
        assertEq(vault.active, true);
        assertEq(vault.openedAt, block.timestamp);
        assertEq(vault.expiresAt, block.timestamp + 1 days);
        assertEq(vault.duration, 1 days);
        assertEq(vault.ltv, 9000);

        // check asset specific info
        assertEq(vault.collateralAsset, WETHAddress);
        assertEq(vault.cashAsset, USDCAddress);
        assertEq(vault.collateralAmount, 100 ether);
        assertEq(vault.cashAmount, 100 ether);

        // check liquidity pool stuff
        assertEq(vault.liquidityPool, address(pool));
        assertEq(vault.lockedPoolCash, 10 ether);
        assertEq(vault.putStrikeTick, 90);
        assertEq(vault.callStrikeTick, 110);
        assertEq(vault.putStrikePrice, 0.9e18);
        assertEq(vault.callStrikePrice, 1.1e18);

        // check vault specific stuff
        assertEq(vault.loanBalance, 90 ether);
        assertEq(vault.lockedVaultCash, 10 ether);
    }
}