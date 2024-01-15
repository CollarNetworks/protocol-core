// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockUniRouter } from "../utils/MockUniRouter.sol";
import { MockEngine } from "../../test/utils/MockEngine.sol";
import { CollarPool } from "../../src/implementations/CollarPool.sol";
import { ICollarPoolState } from "../../src/interfaces/ICollarPool.sol";
import { CollarVaultState } from "../../src/libs/CollarLibs.sol";
import { ICollarVaultManager } from "../../src/interfaces/ICollarVaultManager.sol";
import { CollarVaultManager } from "../../src/implementations/CollarVaultManager.sol";
import { IERC6909WithSupply } from "../../src/interfaces/IERC6909WithSupply.sol";

contract CollarVaultManagerTest is Test {
    TestERC20 token1;
    TestERC20 token2;
    MockUniRouter router;
    MockEngine engine;
    CollarPool pool;
    CollarVaultManager manager;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");

    // below we copy error messages from contracts since they aren't by default "public" or otherwise accessible
    error OwnableUnauthorizedAccount(address account);
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    bytes user1NotAuthorized = abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(user1));

    function setUp() public {
        token1 = new TestERC20("Test1", "TST1");
        token2 = new TestERC20("Test2", "TST2");

        router = new MockUniRouter();
        engine = new MockEngine(address(router));

        pool = new CollarPool(address(engine), 1, address(token2));
        manager = new CollarVaultManager(address(engine), user1);

        engine.addLiquidityPool(address(pool));
        engine.addSupportedCollateralAsset(address(token1));
        engine.addSupportedCashAsset(address(token2));

        token1.mint(address(router), 100_000);
        token2.mint(address(router), 100_000);

        // label everything to make reading the test errors easier
        vm.label(address(manager), "Vault Manager");
        vm.label(address(engine), "Collar Engine");
        vm.label(address(pool), "Collar Pool");

        vm.label(address(token1), "Test Token 1 // Collateral");
        vm.label(address(token2), "Test Token 2 // Cash");

        vm.label(user1, "Test User 1");
        vm.label(user2, "Test User 2");
    }

    function mintTokensToUserAndApprovePool(address user) internal {
        startHoax(user);
        token1.mint(user, 100_000);
        token2.mint(user, 100_000);
        token1.approve(address(pool), 100_000);
        token2.approve(address(pool), 100_000);
        vm.stopPrank();
    }

    function mintTokensToUserAndApproveManager(address user) internal {
        startHoax(user);
        token1.mint(user, 100_000);
        token2.mint(user, 100_000);
        token1.approve(address(manager), 100_000);
        token2.approve(address(manager), 100_000);
        vm.stopPrank();
    }

    function test_deploymentAndDeployParams() public {
        assertEq(manager.owner(), user1);
        assertEq(manager.engine(), address(engine));
        assertEq(manager.vaultCount(), 0);
    }

    function test_openVault() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidity(11_000, 25_000);

        CollarVaultState.AssetSpecifiers memory assets = CollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        CollarVaultState.CollarOpts memory collarOpts = CollarVaultState.CollarOpts({ expiry: block.timestamp + 100, ltv: 9000 });

        CollarVaultState.LiquidityOpts memory liquidityOpts =
            CollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        assertEq(manager.vaultCount(), 1);

        bytes memory vaultInfo = manager.vaultInfo(uuid);

        // grab the vault state & check all the values

        CollarVaultState.Vault memory vault = abi.decode(vaultInfo, (CollarVaultState.Vault));

        assertEq(vault.active, true);
        assertEq(vault.openedAt, 1);
        assertEq(vault.expiresAt, 101);
        assertEq(vault.ltv, 9000);
        assertEq(vault.collateralAsset, address(token1));
        assertEq(vault.collateralAmount, 100);
        assertEq(vault.cashAsset, address(token2));
        assertEq(vault.cashAmount, 100);
        assertEq(vault.liquidityPool, address(pool));
        assertEq(vault.lockedPoolCash, 10);
        assertEq(vault.initialCollateralPrice, 1e18);
        assertEq(vault.putStrikePrice, 0.9e18);
        assertEq(vault.callStrikePrice, 1.1e18);
        assertEq(vault.putStrikeTick, 9000);
        assertEq(vault.callStrikeTick, 11_000);
        assertEq(vault.loanBalance, 90);
        assertEq(vault.lockedVaultCash, 10);
    }

    function test_openVault_InvalidAssetSpecifiers() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidity(11_000, 25_000);

        CollarVaultState.AssetSpecifiers memory invalidCollatAddr = CollarVaultState.AssetSpecifiers({
            collateralAsset: address(token2),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        CollarVaultState.AssetSpecifiers memory invalidCollatAmount = CollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 0,
            cashAsset: address(token2),
            cashAmount: 100
        });

        CollarVaultState.AssetSpecifiers memory invalidCashAmount = CollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 0
        });

        CollarVaultState.AssetSpecifiers memory invalidCashAddr = CollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token1),
            cashAmount: 100
        });

        CollarVaultState.CollarOpts memory collarOpts = CollarVaultState.CollarOpts({ expiry: block.timestamp + 100, ltv: 9000 });

        CollarVaultState.LiquidityOpts memory liquidityOpts =
            CollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        startHoax(user1);
        
        vm.expectRevert("Unsupported collateral asset");
        manager.openVault(invalidCollatAddr, collarOpts, liquidityOpts);

        vm.expectRevert("Collateral amount must be > 0");
        manager.openVault(invalidCollatAmount, collarOpts, liquidityOpts);

        vm.expectRevert("Unsupported cash asset");
        manager.openVault(invalidCashAddr, collarOpts, liquidityOpts);

        vm.expectRevert("Cash amount must be > 0");
        manager.openVault(invalidCashAmount, collarOpts, liquidityOpts);
    }

    function test_openVault_InvalidCollarOpts() public {
        revert("TODO: Need to add in expiry length validation & modification to Engine");


        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidity(11_000, 25_000);

        CollarVaultState.AssetSpecifiers memory assets = CollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        CollarVaultState.CollarOpts memory invalidExpiry = CollarVaultState.CollarOpts({ expiry: block.timestamp + 100, ltv: 9000 });
        CollarVaultState.CollarOpts memory invalidLTV = CollarVaultState.CollarOpts({ expiry: block.timestamp + 100, ltv: 90 });

        CollarVaultState.LiquidityOpts memory liquidityOpts =
            CollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        hoax(user1);
        
        manager.openVault(assets, invalidExpiry, liquidityOpts);

        manager.openVault(assets, invalidLTV, liquidityOpts);
    }

    function test_openVault_InvalidLiquidityOpts() public {
        revert("TODO: Need to add in validation for liquidity opts (in vault manager AND in pool");

        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidity(11_000, 25_000);

        CollarVaultState.AssetSpecifiers memory assets = CollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        CollarVaultState.CollarOpts memory collarOpts = CollarVaultState.CollarOpts({ expiry: block.timestamp + 100, ltv: 9000 });

        CollarVaultState.LiquidityOpts memory invalidPool =
            CollarVaultState.LiquidityOpts({ liquidityPool: address(token1), putStrikeTick: 9000, callStrikeTick: 11_000 });

        CollarVaultState.LiquidityOpts memory invalidPutStrike =
            CollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 900_000, callStrikeTick: 11_000 });

        CollarVaultState.LiquidityOpts memory invalidCallStrike =
            CollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        hoax(user1);
        
        vm.expectRevert("Invalid pool address");
        manager.openVault(assets, collarOpts, invalidPool);

        vm.expectRevert("Invalid put strike");
        manager.openVault(assets, collarOpts, invalidPutStrike);

        vm.expectRevert("Invalid call strike");
        manager.openVault(assets, collarOpts, invalidCallStrike);
    }

    function test_openVault_NotEnoughAssets() public {
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidity(11_000, 25_000);

        CollarVaultState.AssetSpecifiers memory assets = CollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        CollarVaultState.CollarOpts memory collarOpts = CollarVaultState.CollarOpts({ expiry: block.timestamp + 100, ltv: 9000 });

        CollarVaultState.LiquidityOpts memory liquidityOpts =
            CollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        startHoax(user1);

        token1.approve(address(pool), 100_000);
        token1.approve(address(manager), 100_000);

        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, address(user1), 0, 100));
        manager.openVault(assets, collarOpts, liquidityOpts);
    }

    function test_closeVaultNoPriceChange() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidity(11_000, 25_000);

        CollarVaultState.AssetSpecifiers memory assets = CollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        CollarVaultState.CollarOpts memory collarOpts = CollarVaultState.CollarOpts({ expiry: block.timestamp + 100, ltv: 9000 });

        CollarVaultState.LiquidityOpts memory liquidityOpts =
            CollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        skip(100);

        engine.setHistoricalAssetPrice(address(token1), 101, 1e18);

        manager.closeVault(uuid);

        bytes memory vaultInfo = manager.vaultInfo(uuid);

        // check vault info
        CollarVaultState.Vault memory vault = abi.decode(vaultInfo, (CollarVaultState.Vault));

        assertEq(vault.active, false);
        assertEq(vault.openedAt, 1);
        assertEq(vault.expiresAt, 101);
        assertEq(vault.ltv, 9000);
        assertEq(vault.collateralAsset, address(token1));
        assertEq(vault.collateralAmount, 100);
        assertEq(vault.cashAsset, address(token2));
        assertEq(vault.cashAmount, 100);
        assertEq(vault.liquidityPool, address(pool));
        assertEq(vault.lockedPoolCash, 10);
        assertEq(vault.initialCollateralPrice, 1e18);
        assertEq(vault.putStrikePrice, 0.9e18);
        assertEq(vault.callStrikePrice, 1.1e18);
        assertEq(vault.loanBalance, 100);
        assertEq(vault.lockedVaultCash, 0);

        // check to make sure that the pool got the free 10 cash tokens as a reward
        assertEq(token2.balanceOf(address(manager)), 100);
    }

    function test_closeVaultNoCollateralPriceUp() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidity(11_000, 25_000);

        CollarVaultState.AssetSpecifiers memory assets = CollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        CollarVaultState.CollarOpts memory collarOpts = CollarVaultState.CollarOpts({ expiry: block.timestamp + 100, ltv: 9000 });

        CollarVaultState.LiquidityOpts memory liquidityOpts =
            CollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        skip(100);

        engine.setHistoricalAssetPrice(address(token1), 101, 2e18);

        manager.closeVault(uuid);

        bytes memory vaultInfo = manager.vaultInfo(uuid);

        // check vault info
        CollarVaultState.Vault memory vault = abi.decode(vaultInfo, (CollarVaultState.Vault));

        assertEq(vault.active, false);
        assertEq(vault.openedAt, 1);
        assertEq(vault.expiresAt, 101);
        assertEq(vault.ltv, 9000);
        assertEq(vault.collateralAsset, address(token1));
        assertEq(vault.collateralAmount, 100);
        assertEq(vault.cashAsset, address(token2));
        assertEq(vault.cashAmount, 100);
        assertEq(vault.liquidityPool, address(pool));
        assertEq(vault.lockedPoolCash, 10);
        assertEq(vault.initialCollateralPrice, 1e18);
        assertEq(vault.putStrikePrice, 0.9e18);
        assertEq(vault.callStrikePrice, 1.1e18);
        assertEq(vault.loanBalance, 110);
        assertEq(vault.lockedVaultCash, 0);

        // check to make sure that the vault got the free 10 cash tokens as a reward
        assertEq(token2.balanceOf(address(manager)), 110);
    }

    function test_closeVaultNoCollateralPriceDown() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidity(11_000, 25_000);

        CollarVaultState.AssetSpecifiers memory assets = CollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        CollarVaultState.CollarOpts memory collarOpts = CollarVaultState.CollarOpts({ expiry: block.timestamp + 100, ltv: 9000 });

        CollarVaultState.LiquidityOpts memory liquidityOpts =
            CollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        skip(100);

        engine.setHistoricalAssetPrice(address(token1), 101, 0);

        manager.closeVault(uuid);

        bytes memory vaultInfo = manager.vaultInfo(uuid);

        // check vault info
        CollarVaultState.Vault memory vault = abi.decode(vaultInfo, (CollarVaultState.Vault));

        assertEq(vault.active, false);
        assertEq(vault.openedAt, 1);
        assertEq(vault.expiresAt, 101);
        assertEq(vault.ltv, 9000);
        assertEq(vault.collateralAsset, address(token1));
        assertEq(vault.collateralAmount, 100);
        assertEq(vault.cashAsset, address(token2));
        assertEq(vault.cashAmount, 100);
        assertEq(vault.liquidityPool, address(pool));
        assertEq(vault.lockedPoolCash, 10);
        assertEq(vault.initialCollateralPrice, 1e18);
        assertEq(vault.putStrikePrice, 0.9e18);
        assertEq(vault.callStrikePrice, 1.1e18);
        assertEq(vault.loanBalance, 90);
        assertEq(vault.lockedVaultCash, 0);

        // check to make sure that the pool got the free 10 cash tokens as a reward
        assertEq(token2.balanceOf(address(manager)), 90);
    }

    function test_closeVault_AlreadyClosed() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidity(11_000, 25_000);

        CollarVaultState.AssetSpecifiers memory assets = CollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        CollarVaultState.CollarOpts memory collarOpts = CollarVaultState.CollarOpts({ expiry: block.timestamp + 100, ltv: 9000 });

        CollarVaultState.LiquidityOpts memory liquidityOpts =
            CollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token2), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        skip(100);

        engine.setHistoricalAssetPrice(address(token2), 101, 1e18);

        manager.closeVault(uuid);

        vm.expectRevert("Vault not active or not finalizable");
        manager.closeVault(uuid);
    }

    function test_closeVault_InvalidVault() public {
        vm.expectRevert("Vault does not exist");
        manager.closeVault(bytes32(0));
    }

    function test_closeVault_NotExpired() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidity(11_000, 25_000);

        CollarVaultState.AssetSpecifiers memory assets = CollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        CollarVaultState.CollarOpts memory collarOpts = CollarVaultState.CollarOpts({ expiry: block.timestamp + 100, ltv: 9000 });

        CollarVaultState.LiquidityOpts memory liquidityOpts =
            CollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token2), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        vm.expectRevert("Vault not active or not finalizable");
        manager.closeVault(uuid);

        // advance some blocks, but not all of them!
        skip(25);

        vm.expectRevert("Vault not active or not finalizable");
        manager.closeVault(uuid);
    }

    function test_redeem() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidity(11_000, 25_000);

        CollarVaultState.AssetSpecifiers memory assets = CollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        CollarVaultState.CollarOpts memory collarOpts = CollarVaultState.CollarOpts({ expiry: block.timestamp + 100, ltv: 9000 });

        CollarVaultState.LiquidityOpts memory liquidityOpts =
            CollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token2), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        skip(100);

        engine.setHistoricalAssetPrice(address(token2), 101, 1e18);

        manager.closeVault(uuid);

        IERC6909WithSupply token = IERC6909WithSupply(manager);
        assertEq(token.totalTokenSupply(uint256(uuid)), 100);
    }

    function test_redeem_InvalidVault() public {
        revert("TODO");
    }

    function test_redeem_InvalidAmount() public {
        revert("TODO");
    }

    function test_redeem_NotFinalized() public {
        revert("TODO");
    }

    function test_redeem_NotApproved() public {
        revert("TODO");
    }

    function test_previewRedeem() public {
        revert("TODO");
    }

    function test_previewRedeem_NotFinalized() public {
        revert("TODO");
    }

    function test_previewRedeem_InvalidVault() public {
        revert("TODO");
    }

    function test_previewRedeem_InvalidAmount() public {
        revert("TODO");
    }

    function test_withdraw() public {
        revert("TODO");
    }

    function test_withdraw_TooMuch() public {
        revert("TODO");
    }

    function test_withdraw_NoAuth() public {
        revert("TODO");
    }

    function test_withdraw_InvalidVault() public {
        revert("TODO");
    }

    function test_vaultInfo_InvalidVault() public {
        vm.expectRevert("Vault does not exist");
        manager.vaultInfo(bytes32(0));
    }
}
