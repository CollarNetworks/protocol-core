// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import { TestERC20 } from "../../utils/TestERC20.sol";
import { CollarVaultState, CollarVaultConstants } from "../../../src/vaults/interfaces/CollarLibs.sol";
import { CollarVaultManager } from "../../../src/vaults/implementations/CollarVaultManager.sol";
import { CollarLiquidityPool } from "../../../src/liquidity/implementations/CollarLiquidityPool.sol";
import { CollarEngine } from "../../../src/protocol/implementations/Engine.sol";
import { MockUniRouter } from "../../utils/MockUniRouter.sol";

contract CollarVaultManagerTest is Test {
    TestERC20 collateral;
    TestERC20 cash;
    CollarVaultManager manager;
    CollarLiquidityPool pool;
    CollarEngine engine;
    MockUniRouter router;

    function setUp() public {
        // create contracts
        collateral = new TestERC20("Collateral", "CLT");
        cash = new TestERC20("Cash", "CSH");
        pool = new CollarLiquidityPool(address(cash));
        router = new MockUniRouter();
        engine = new CollarEngine(address(this), address(manager), address(router));
        manager = new CollarVaultManager(address(engine), address(this));
    }

    function test_createVault() public {
        // 1/3 params for vault creation
        CollarVaultState.AssetSpecifiers memory assetOpts = CollarVaultState.AssetSpecifiers(
            address(collateral),
            1000e18,    // we want to deposit 1000 tokens of collateral
            address(cash),
            1000e18     // we are expecting this to swap for, at minimum, 1000 tokens of cash
        );

        // 2/3 params for vault creation
        CollarVaultState.CollarOpts memory collarOpts = CollarVaultState.CollarOpts(
            block.timestamp + 3 days,   // vault expiry will be in 3 days
            9_000                       // 90% ltv
        );

        // we're going to pull from a single tick in the liquidity pool - representing a callstrike of 110% the current price
        uint24[] memory ticks = new uint24[](1);
        ticks[0] = 11_000;

        // we're going to need to lock 100 tokens of liquidity in this tick to cover the call-striek point
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100e18;

        // 3/3 params for vault creation
        CollarVaultState.LiquidityOpts memory liquidityOpts = CollarVaultState.LiquidityOpts(
            address(pool),
            ticks,
            amounts
        );

        // mint ourselves cash so we can deposit to the liquidity pool
        cash.mint(address(this), 2000e18);
        cash.approve(address(pool), 2000e18);
        pool.depositToTicks(address(this), amounts, ticks);

        // add the cash and collateral assets and collar length of 3 days to the engine as valid options for collars
        engine.addSupportedCashAsset(address(cash));
        engine.addSupportedCollateralAsset(address(collateral));
        engine.addSupportedCollarLength(3 days);

        // mint ourselves collateral and the mock uniswap router some cash so the vault manager can perform the swap
        collateral.mint(address(this), 5000e18);
        cash.mint(address(router), 5000e18);
        collateral.approve(address(manager), 5000e18);

        // finally, open the vault
        bytes32 uuid = manager.openVault(
            assetOpts,
            collarOpts,
            liquidityOpts
        );

        // there should only be one vault that exists for this manager
        assertEq(manager.vaultCount(), 1);

        // grab the vault state so we can check it
        CollarVaultState.Vault memory vault = manager.getVault(uuid);

        assertEq(vault.collateralAsset, address(collateral));
        assertEq(vault.collateralAmount, 1000e18);
        assertEq(vault.cashAsset, address(cash));
        assertEq(vault.cashAmount, 1000e18);

        assertEq(vault.unlockedCashBalance, 900e18); // unlocked cash balance should be ltv * starting (90% * 1000 = 900)
        assertEq(vault.lockedCashBalance, 100e18);   // locked cash balance should be the remainder from unlocked (100)

        assertEq(vault.liquidityPool, address(pool));
        assertEq(vault.ticks.length, 1);
        assertEq(vault.ticks[0], 11_000);

        assertEq(vault.amounts.length, 1);
        assertEq(vault.amounts[0], 100e18);
    }
}