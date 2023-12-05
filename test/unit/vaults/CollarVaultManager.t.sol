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
import { MockEngine } from "../../utils/MockEngine.sol";
import { MockUniRouter } from "../../utils/MockUniRouter.sol";
import { ArrayHelpersUint24, ArrayHelpersUint256 } from "../../utils/ArrayHelpers.sol";

contract CollarVaultManagerTest is Test {
    TestERC20 collateral;
    TestERC20 cash;
    CollarVaultManager manager;
    CollarLiquidityPool pool;
    MockEngine engine;
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
        engine = new MockEngine(address(this), address(manager), address(router));
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
        uint256 poolDepositAmount = 100e18; // 100 tokens of liquidity to be locked @ callstrike
        uint24 callstriketick = 11_000; // callstrike @ 110%
        uint24 putstriketick = 9_000; // putstrike @ 90%
        CollarVaultState.LiquidityOpts memory liquidityOpts = CollarVaultState.LiquidityOpts(address(pool), poolDepositAmount, putstriketick, callstriketick);

        // deposit to the liquidity pool
        pool.deposit(address(this), poolDepositAmount, callstriketick);

        // open the vault
        bytes32 uuid = manager.open(defaultAssetOpts, defaultCollarOpts, liquidityOpts);

        // there should only be one vault that exists for this manager
        assertEq(manager.vaultCount(), 1);

        // grab the vault state so we can check it
        CollarVaultState.Vault memory vault = manager.getVault(uuid);

        // default: 1000 collateral tokens <==swap==> 1000 cash tokens @ 90% LTV ==> 900 unlocked & 100 locked

        // check assets & amounts
        assertEq(vault.collateralAsset, address(collateral));
        assertEq(vault.collateralAmount, 1000e18);
        assertEq(vault.cashAsset, address(cash));
        assertEq(vault.cashAmount, 1000e18);

        // check unlocked & locked amounts
        assertEq(vault.unlockedVaultCash, 900e18);
        assertEq(vault.lockedVaultCash, 100e18);

        // check call & put strike ticks
        assertEq(vault.callStrikeTick, 11_000);
        assertEq(vault.putStrikeTick, 9_000);

        // check specific locked liquidity amounts
        assertEq(pool.lockedliquidityAtTick(11_000), 100e18);
        assertEq(pool.liquidityAtTickByAddress(11_000, address(this)), 100e18);
    }

    function test_withdraw() public {
        // create liquidity options
        uint256 poolDepositAmount = 100e18; // 100 tokens of liquidity to be locked @ callstrike
        uint24 callstriketick = 11_000; // callstrike @ 110%
        uint24 putstriketick = 9_000; // putstrike @ 90%
        CollarVaultState.LiquidityOpts memory liquidityOpts = CollarVaultState.LiquidityOpts(address(pool), poolDepositAmount, putstriketick, callstriketick);

        // deposit to the liquidity pool
        pool.deposit(address(this), poolDepositAmount, callstriketick);

        // open the vault
        bytes32 uuid = manager.open(defaultAssetOpts, defaultCollarOpts, liquidityOpts);

        // grab the vault state so we can check it
        CollarVaultState.Vault memory vault = manager.getVault(uuid);

        // default: 1000 collateral tokens <==swap==> 1000 cash tokens @ 90% LTV ==> 900 unlocked & 100 locked

        assertEq(vault.unlockedVaultCash, 900e18);
        assertEq(vault.lockedVaultCash, 100e18);

        // withdraw all 100 tokens frrom the vault
        manager.withdraw(uuid, 100e18, address(this));

        // grab the vault from storage again since we're using a mem ref and not a storage ref
        vault = manager.getVault(uuid);

        // vault should have 800 unlocked & 100 locked tokens
        assertEq(vault.unlockedVaultCash, 800e18);
        assertEq(vault.lockedVaultCash, 100e18);
    }

    function test_withdrawTooMuch() public {
        // create liquidity options
        uint256 poolDepositAmount = 100e18; // 100 tokens of liquidity to be locked @ callstrike
        uint24 callstriketick = 11_000; // callstrike @ 110%
        uint24 putstriketick = 9_000; // putstrike @ 90%
        CollarVaultState.LiquidityOpts memory liquidityOpts = CollarVaultState.LiquidityOpts(address(pool), poolDepositAmount, putstriketick, callstriketick);

        // deposit to the liquidity pool
        pool.deposit(address(this), poolDepositAmount, callstriketick);

        // open the vault
        bytes32 uuid = manager.open(defaultAssetOpts, defaultCollarOpts, liquidityOpts);

        // grab the vault state so we can check it
        CollarVaultState.Vault memory vault = manager.getVault(uuid);

        // default: 1000 collateral tokens <==swap==> 1000 cash tokens @ 90% LTV ==> 900 unlocked & 100 locked

        // withdraw from the vault - 901 tokens should cause underflow / error
        vm.expectRevert();
        manager.withdraw(uuid, 901e18, address(this));
    }
    
    function test_deposit() public {
        // create liquidity options
        uint256 poolDepositAmount = 100e18; // 100 tokens of liquidity to be locked @ callstrike
        uint24 callstriketick = 11_000; // callstrike @ 110%
        uint24 putstriketick = 9_000; // putstrike @ 90%
        CollarVaultState.LiquidityOpts memory liquidityOpts = CollarVaultState.LiquidityOpts(address(pool), poolDepositAmount, putstriketick, callstriketick);

        // deposit to the liquidity pool
        pool.deposit(address(this), poolDepositAmount, callstriketick);

        // set the price of the asset
        engine.setCurrentAssetPrice(address(collateral), 1e18);

        // open the vault
        bytes32 uuid = manager.open(defaultAssetOpts, defaultCollarOpts, liquidityOpts);

        // grab the vault state so we can check it
        CollarVaultState.Vault memory vault = manager.getVault(uuid);

        // default: 1000 collateral tokens <==swap==> 1000 cash tokens @ 90% LTV ==> 900 unlocked & 100 locked

        assertEq(vault.unlockedVaultCash, 900e18);
        assertEq(vault.lockedVaultCash, 100e18);

        // deposit cash
        manager.deposit(uuid, 100e18, address(this));

        // grab the vault from storage again since we're using a mem ref and not a storage ref
        vault = manager.getVault(uuid);
        
        // after depositing 100 additional cash ==> 1000 unlocked & 100 locked
        assertEq(vault.unlockedVaultCash, 1000e18);
        assertEq(vault.lockedVaultCash, 100e18);
    }

    /*
    function test_finalizeVault() public {
        // create liquidity options
        uint256 total = 100e18; // 100 tokens of liquidity to be locked @ callstrike
        uint24[] memory ticks = ArrayHelpersUint24.uint24Array(11_000); // callstrike @ 110%
        uint256[] memory ratios = ArrayHelpersUint256.uint256Array(1e12); // all tokens to be locked at the one tick
        CollarVaultState.LiquidityOpts memory liquidityOpts = CollarVaultState.LiquidityOpts(address(pool), total, ticks, ratios);

        // deposit to the liquidity pool
        uint256[] memory amounts = ArrayHelpersUint256.uint256Array(total);
        pool.deposit(address(this), amounts, ticks);

        // open the vault
        bytes32 uuid = manager.openVault(defaultAssetOpts, defaultCollarOpts, liquidityOpts);

        // grab the vault state so we can check it
        CollarVaultState.Vault memory vault = manager.getVault(uuid);

        // set the historical asset price @ vault close
        uint256 vaultExpiryCalculated = vault.opened + 3 days;
        uint256 vaultExpiryActual = vault.expiry;

        assertEq(vaultExpiryCalculated, vaultExpiryActual);

        // price is in terms of cash per collateral
        // but in the vault, we compare price as if its the total amount of cash we got for our collateral
        // thus we need to multiply
        // we'll use a precision multiplier of 1e12 for now
        // and we'll set the price to have gone from 1000 --> 500
        engine.setHistoricalAssetPrice(address(collateral), vaultExpiryActual, 500e18 * 1e12);

        // finalize the vault
        manager.finalizeVault(uuid);

        // grab the vault state so we can check it
        vault = manager.getVault(uuid);

        assertEq(vault.unlockedVaultCash, 0);
        assertEq(vault.lockedVaultCash, 0);
        assertEq(vault.collateralAmount, 0);
        assertEq(vault.cashAmount, 0);
        assertEq(vault.tickRatios.length, 1);
        assertEq(vault.callStrikeTicks.length, 1);
    }*/
}