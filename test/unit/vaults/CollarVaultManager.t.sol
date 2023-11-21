// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { TestERC20 } from "../../utils/TestERC20.sol";
import { CollarVaultState, CollarVaultConstants } from "../../../src/vaults/interfaces/CollarLibs.sol";
import { CollarVaultManager } from "../../../src/vaults/implementations/CollarVaultManager.sol";
import { CollarLiquidityPool } from "../../../src/liquidity/implementations/CollarLiquidityPool.sol";
import { CollarEngine } from "../../../src/protocol/implementations/Engine.sol";
import { MockUniRouter } from "../../utils/MockUniRouter.sol";
import { ArrayHelpersUint24, ArrayHelpersUint256 } from "../../utils/ArrayHelpers.sol";

contract CollarVaultManagerTest is Test {
    TestERC20 collateral;
    TestERC20 cash;
    CollarVaultManager manager;
    CollarLiquidityPool pool;
    CollarEngine engine;
    MockUniRouter router;

    CollarVaultState.AssetSpecifiers defaultAssetOpts;
    CollarVaultState.CollarOpts defaultCollarOpts;
    CollarVaultState.LiquidityOpts defaultLiquidityOpts;

    function setUp() public {
        // create contracts
        collateral = new TestERC20("Collateral", "CLT");
        cash = new TestERC20("Cash", "CSH");
        pool = new CollarLiquidityPool(address(cash), 1); // 0.01% per tick 
        router = new MockUniRouter();
        engine = new CollarEngine(address(this), address(manager), address(router));
        manager = new CollarVaultManager(address(engine), address(this));

        // set up some default vars to be used in (some) tests
        defaultAssetOpts = CollarVaultState.AssetSpecifiers(
            address(collateral),
            1000e18,    // we want to deposit 1000 tokens of collateral
            address(cash),
            1000e18     // we are expecting this to swap for, at minimum, 1000 tokens of cash
        );

        defaultCollarOpts = CollarVaultState.CollarOpts(
            block.timestamp + 3 days,   // vault expiry will be in 3 days
            9_000                       // 90% ltv
        );

        // mint & approve cash
        cash.mint(address(this), 10_000e18);
        cash.mint(address(router), 10_000e18);
        cash.approve(address(pool), 10_000e18);
        cash.approve(address(router), 10_000e18);
        cash.approve(address(manager), 10_000e18);

        // mint & approve collateral
        collateral.mint(address(this), 10_000e18);
        collateral.approve(address(manager), 10_000e18);

        // add the cash and collateral assets and default collar length of 3 days to the engine as valid options for collars
        engine.addSupportedCashAsset(address(cash));
        engine.addSupportedCollateralAsset(address(collateral));
        engine.addSupportedCollarLength(3 days);
    }

    function test_createVaultSingleTickLiquidity() public {
        // create liquidity options
        uint24[] memory ticks = ArrayHelpersUint24.uint24Array(11_000);      // callstrike @ 110%
        uint256[] memory amounts = ArrayHelpersUint256.uint256Array(100e18); // 100 tokens of liqudity to be locked @ callstrike
        CollarVaultState.LiquidityOpts memory liquidityOpts = CollarVaultState.LiquidityOpts(address(pool), ticks, amounts);

        // deposit to the liquidity pool
        pool.depositToTicks(address(this), amounts, ticks);

        // open the vault
        bytes32 uuid = manager.openVault(defaultAssetOpts, defaultCollarOpts, liquidityOpts);

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

        assertEq(pool.lockedliquidityAtTick(11_000), 100e18);
        assertEq(pool.liquidityAtTickByAddress(11_000, address(this)), 100e18);
    }

    function test_createVaultMultiTickLiquidity() public {
        // 110%, 120%, 130% @ 100, 100, 100 tokens of liquidity
        uint24[] memory ticks = ArrayHelpersUint24.uint24Array(11_000, 12_000, 13_000);
        uint256[] memory amounts = ArrayHelpersUint256.uint256Array(100e18, 100e18, 100e18); 
        CollarVaultState.LiquidityOpts memory liquidityOpts = CollarVaultState.LiquidityOpts(address(pool), ticks, amounts);

        // deposit to the liquidity pool
        pool.depositToTicks(address(this), amounts, ticks);

        // open the vault
        bytes32 uuid = manager.openVault(defaultAssetOpts, defaultCollarOpts, liquidityOpts);

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

        assertEq(vault.ticks.length, 3);
        assertEq(vault.ticks[0], 11_000);
        assertEq(vault.ticks[1], 12_000);
        assertEq(vault.ticks[2], 13_000);

        assertEq(vault.amounts.length, 3);
        assertEq(vault.amounts[0], 100e18);
        assertEq(vault.amounts[1], 100e18);
        assertEq(vault.amounts[2], 100e18);

        assertEq(pool.lockedliquidityAtTick(11_000), 100e18);
        assertEq(pool.liquidityAtTickByAddress(11_000, address(this)), 100e18);
        assertEq(pool.lockedliquidityAtTick(12_000), 100e18);
        assertEq(pool.liquidityAtTickByAddress(12_000, address(this)), 100e18);
        assertEq(pool.lockedliquidityAtTick(13_000), 100e18);
        assertEq(pool.liquidityAtTickByAddress(13_000, address(this)), 100e18);
    }

    function test_withdrawCash() public {
        // create liquidity options
        uint24[] memory ticks = ArrayHelpersUint24.uint24Array(11_000);      // callstrike @ 110%
        uint256[] memory amounts = ArrayHelpersUint256.uint256Array(100e18); // 100 tokens of liqudity to be locked @ callstrike
        CollarVaultState.LiquidityOpts memory liquidityOpts = CollarVaultState.LiquidityOpts(address(pool), ticks, amounts);

        // deposit to the liquidity pool
        pool.depositToTicks(address(this), amounts, ticks);

        // open the vault
        bytes32 uuid = manager.openVault(defaultAssetOpts, defaultCollarOpts, liquidityOpts);

        // withdraw from the vault
        manager.withdrawCash(uuid, 50e18, address(this)); // half of our loan to us
        manager.withdrawCash(uuid, 50e18, address(0x1337)); // the other half of our loan 0x1337

        uint256 ourBalance = cash.balanceOf(address(this));
        uint256 otherBalance = cash.balanceOf(address(0x1337));

        assertEq(ourBalance, 9950e18);
        assertEq(otherBalance, 50e18);

        // grab the vault state so we can check it
        CollarVaultState.Vault memory vault = manager.getVault(uuid);

        assertEq(vault.unlockedCashBalance, 800e18);
        assertEq(vault.lockedCashBalance, 100e18);
    }

    function test_withdrawTooMuchCash() public {
        // create liquidity options
        uint24[] memory ticks = ArrayHelpersUint24.uint24Array(11_000);      // callstrike @ 110%
        uint256[] memory amounts = ArrayHelpersUint256.uint256Array(100e18); // 100 tokens of liqudity to be locked @ callstrike
        CollarVaultState.LiquidityOpts memory liquidityOpts = CollarVaultState.LiquidityOpts(address(pool), ticks, amounts);

        // deposit to the liquidity pool
        pool.depositToTicks(address(this), amounts, ticks);

        // open the vault
        bytes32 uuid = manager.openVault(defaultAssetOpts, defaultCollarOpts, liquidityOpts);

        // withdraw from the vault
        vm.expectRevert();
        manager.withdrawCash(uuid, 901e18, address(this));
    }
    
    function test_depositCash() public {
        // create liquidity options
        uint24[] memory ticks = ArrayHelpersUint24.uint24Array(11_000);      // callstrike @ 110%
        uint256[] memory amounts = ArrayHelpersUint256.uint256Array(100e18); // 100 tokens of liqudity to be locked @ callstrike
        CollarVaultState.LiquidityOpts memory liquidityOpts = CollarVaultState.LiquidityOpts(address(pool), ticks, amounts);

        // deposit to the liquidity pool
        pool.depositToTicks(address(this), amounts, ticks);

        // open the vault
        bytes32 uuid = manager.openVault(defaultAssetOpts, defaultCollarOpts, liquidityOpts);

        // deposit cash to the vault
        manager.depositCash(uuid, 100e18, address(this));

        uint256 ourBalance = cash.balanceOf(address(this));
        uint256 vaultBalance = cash.balanceOf(address(manager));

        assertEq(ourBalance, 9800e18);
        assertEq(vaultBalance, 1100e18);

        // grab the vault state so we can check it
        CollarVaultState.Vault memory vault = manager.getVault(uuid);

        assertEq(vault.unlockedCashBalance, 1000e18);
        assertEq(vault.lockedCashBalance, 100e18);
    }

    /*
    function test_finalizeVault() public {
        // create liquidity options
        uint24[] memory ticks = ArrayHelpersUint24.uint24Array(11_000);      // callstrike @ 110%
        uint256[] memory amounts = ArrayHelpersUint256.uint256Array(100e18); // 100 tokens of liqudity to be locked @ callstrike
        CollarVaultState.LiquidityOpts memory liquidityOpts = CollarVaultState.LiquidityOpts(address(pool), ticks, amounts);

        // deposit to the liquidity pool
        pool.depositToTicks(address(this), amounts, ticks);

        // open the vault
        bytes32 uuid = manager.openVault(defaultAssetOpts, defaultCollarOpts, liquidityOpts);

        // finalize the vault
        manager.finalizeVault(uuid);

        // grab the vault state so we can check it
        CollarVaultState.Vault memory vault = manager.getVault(uuid);

        assertEq(vault.unlockedCashBalance, 0);
        assertEq(vault.lockedCashBalance, 0);
        assertEq(vault.collateralAmount, 0);
        assertEq(vault.cashAmount, 0);
        assertEq(vault.ticks.length, 0);
        assertEq(vault.amounts.length, 0);
    }
    */
}