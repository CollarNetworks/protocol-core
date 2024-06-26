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
import { MockBadUniRouter } from "../utils/MockBadUniRouter.sol";
import { MockEngine } from "../../test/utils/MockEngine.sol";
import { CollarPool } from "../../src/implementations/CollarPool.sol";
import { ICollarVaultState } from "../../src/interfaces/ICollarVaultState.sol";
import { ICollarVaultManager } from "../../src/interfaces/ICollarVaultManager.sol";
import { CollarVaultManager } from "../../src/implementations/CollarVaultManager.sol";
import { ERC6909TokenSupply } from "@erc6909/ERC6909TokenSupply.sol";

contract CollarVaultManagerTest is Test {
    TestERC20 cashAsset;
    TestERC20 collateralAsset;
    MockUniRouter router;
    MockBadUniRouter badRouter;
    MockEngine engine;
    MockEngine badEngine;
    CollarPool pool;
    CollarPool badPool;
    CollarVaultManager manager;
    CollarVaultManager badManager;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");

    // below we copy error messages from contracts since they aren't by default "public" or otherwise
    // accessible
    error OwnableUnauthorizedAccount(address account);
    error ERC20InsufficientBalance(address sender, uint balance, uint needed);

    bytes user1NotAuthorized = abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(user1));

    function setUp() public {
        cashAsset = new TestERC20("Test1", "TST1");
        collateralAsset = new TestERC20("Test2", "TST2");

        router = new MockUniRouter();
        engine = new MockEngine(address(router));
        engine.addLTV(9000);

        pool = new CollarPool(address(engine), 100, address(cashAsset), address(collateralAsset), 100, 9000);

        cashAsset.approve(address(pool), 100_000 ether);
        cashAsset.mint(address(this), 100_000 ether);
        pool.addLiquidityToSlot(110, 25_000);

        hoax(user1);
        manager = CollarVaultManager(engine.createVaultManager());

        engine.addLiquidityPool(address(pool));
        engine.addSupportedCollateralAsset(address(collateralAsset));
        engine.addSupportedCashAsset(address(cashAsset));
        engine.addCollarDuration(100);

        cashAsset.mint(address(router), 100_000 ether);
        collateralAsset.mint(address(router), 100_000 ether);

        // label everything to make reading the test errors easier
        vm.label(address(manager), "Vault Manager");
        vm.label(address(engine), "Collar Engine");
        vm.label(address(pool), "Collar Pool");

        vm.label(address(collateralAsset), "Test Token 1 // Collateral");
        vm.label(address(cashAsset), "Test Token 2 // Cash");

        vm.label(user1, "Test User 1");
        vm.label(user2, "Test User 2");
        /**
         * setup "bad" versions of the contracts in which the router will swap the wrong amount of tokens
         */
        badRouter = new MockBadUniRouter();
        badEngine = new MockEngine(address(badRouter));
        badEngine.addLTV(9000);
        badPool =
            new CollarPool(address(badEngine), 100, address(cashAsset), address(collateralAsset), 100, 9000);
        cashAsset.approve(address(badPool), 100_000 ether);

        badPool.addLiquidityToSlot(110, 25_000);
        hoax(user1);
        badManager = CollarVaultManager(badEngine.createVaultManager());
        badEngine.addLiquidityPool(address(badPool));
        badEngine.addSupportedCollateralAsset(address(collateralAsset));
        badEngine.addSupportedCashAsset(address(cashAsset));
        badEngine.addCollarDuration(100);
        cashAsset.mint(address(badRouter), 100_000 ether);
        collateralAsset.mint(address(badRouter), 100_000 ether);
        vm.label(address(manager), "Bad Vault Manager (bad swap)");
        vm.label(address(badEngine), "Bad Collar Engine (bad swap)");
        vm.label(address(badPool), "Bad Collar Pool (bad swap) ");
    }

    function mintTokensToUserAndApprovePool(address user) public {
        startHoax(user);
        collateralAsset.mint(user, 100_000);
        cashAsset.mint(user, 100_000);
        collateralAsset.approve(address(pool), 100_000);
        cashAsset.approve(address(pool), 100_000);
        vm.stopPrank();
    }

    function mintTokensToUserAndApproveManager(address user) public {
        startHoax(user);
        collateralAsset.mint(user, 100_000);
        cashAsset.mint(user, 100_000);
        collateralAsset.approve(address(manager), 100_000);
        cashAsset.approve(address(manager), 100_000);
        collateralAsset.approve(address(badManager), 100_000);
        cashAsset.approve(address(badManager), 100_000);
        vm.stopPrank();
    }

    function test_getVaultUUID() public {
        mintTokensAddLiquidityAndOpenVault(false);
        bytes32 calculatedUUID = keccak256(abi.encodePacked(user1, uint(0)));

        assertEq(manager.vaultCount(), 1);
        assertEq(calculatedUUID, manager.vaultUUIDsByIndex(0));
    }

    function test_vaultInfoByIndex() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);

        assertEq(manager.vaultCount(), 1);

        ICollarVaultState.Vault memory infoViaUUID = manager.vaultInfo(uuid);
        ICollarVaultState.Vault memory infoViaIndex = manager.vaultInfoByIndex(0);

        assertEq(infoViaUUID.expiresAt, infoViaIndex.expiresAt);
    }

    function test_vaultInfoByIndex_InvalidVault() public view {
        ICollarVaultState.Vault memory vault = manager.vaultInfoByIndex(0);
        assertEq(vault.expiresAt, 0);
    }

    function test_deploymentAndDeployParams() public view {
        assertEq(manager.owner(), user1);
        assertEq(manager.engine(), address(engine));
        assertEq(manager.vaultCount(), 0);
        assertEq(pool.tickScaleFactor(), 100);
    }

    function test_openVault() public {
        mintTokensAddLiquidityAndOpenVault(false);

        bytes32 calculatedUUID = keccak256(abi.encodePacked(user1, uint(0)));

        assertEq(manager.vaultCount(), 1);
        assertEq(manager.vaultUUIDsByIndex(0), calculatedUUID);

        // grab the vault state & check all the values

        ICollarVaultState.Vault memory vault = manager.vaultInfo(calculatedUUID);

        assertEq(vault.active, true);
        assertEq(vault.openedAt, 1);
        assertEq(vault.expiresAt, 101);
        assertEq(vault.ltv, 9000);
        assertEq(vault.collateralAsset, address(collateralAsset));
        assertEq(vault.collateralAmount, 100);
        assertEq(vault.cashAsset, address(cashAsset));
        assertEq(vault.cashAmount, 100);
        assertEq(vault.liquidityPool, address(pool));
        assertEq(vault.lockedPoolCash, 10);
        assertEq(vault.initialCollateralPrice, 1e18);
        assertEq(vault.putStrikePrice, 0.9e18);
        assertEq(vault.callStrikePrice, 1.1e18);
        assertEq(vault.putStrikeTick, 90);
        assertEq(vault.callStrikeTick, 110);
        assertEq(vault.loanBalance, 90);
        assertEq(vault.lockedVaultCash, 10);
    }

    function test_openVaultAndWithdraw() public {
        mintTokensToUserAndApproveManager(user1);
        uint initialUserCashBalance = cashAsset.balanceOf(user1);
        addLiquidityToPoolAsUser(user2);
        bytes32 uuid = openVaultAsUser(user1, true);

        bytes32 calculatedUUID = keccak256(abi.encodePacked(user1, uint(0)));
        assertEq(uuid, calculatedUUID);

        assertEq(manager.vaultCount(), 1);
        assertEq(manager.vaultUUIDsByIndex(0), calculatedUUID);

        uint userCashBalance = cashAsset.balanceOf(user1);
        assertEq(userCashBalance, initialUserCashBalance + 90);
        // grab the vault state & check all the values
        ICollarVaultState.Vault memory vault = manager.vaultInfo(calculatedUUID);
        assertEq(vault.active, true);
        assertEq(vault.openedAt, 1);
        assertEq(vault.expiresAt, 101);
        assertEq(vault.ltv, 9000);
        assertEq(vault.collateralAsset, address(collateralAsset));
        assertEq(vault.collateralAmount, 100);
        assertEq(vault.cashAsset, address(cashAsset));
        assertEq(vault.cashAmount, 100);
        assertEq(vault.liquidityPool, address(pool));
        assertEq(vault.lockedPoolCash, 10);
        assertEq(vault.initialCollateralPrice, 1e18);
        assertEq(vault.putStrikePrice, 0.9e18);
        assertEq(vault.callStrikePrice, 1.1e18);
        assertEq(vault.putStrikeTick, 90);
        assertEq(vault.callStrikeTick, 110);
        /**
         * loan balance 0 cause we withdrew it all
         */
        assertEq(vault.loanBalance, 0);
        assertEq(vault.lockedVaultCash, 10);
    }

    function test_openVault_InvalidAssetSpecifiers() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory invalidCollatAddr = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(cashAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            minCashAmount: 100
        });

        ICollarVaultState.AssetSpecifiers memory invalidCollatAmount = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 0,
            cashAsset: address(cashAsset),
            minCashAmount: 100
        });

        ICollarVaultState.AssetSpecifiers memory invalidCashAmount = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            minCashAmount: 0
        });

        ICollarVaultState.AssetSpecifiers memory invalidCashAddr = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(collateralAsset),
            minCashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts =
            ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts = ICollarVaultState.LiquidityOpts({
            liquidityPool: address(pool),
            putStrikeTick: 9000,
            callStrikeTick: 11_000
        });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);

        vm.expectRevert("invalid collateral asset");
        manager.openVault(invalidCollatAddr, collarOpts, liquidityOpts, false);

        vm.expectRevert("invalid amount");
        manager.openVault(invalidCollatAmount, collarOpts, liquidityOpts, false);

        vm.expectRevert("invalid cash asset");
        manager.openVault(invalidCashAddr, collarOpts, liquidityOpts, false);

        vm.expectRevert("invalid amount");
        manager.openVault(invalidCashAmount, collarOpts, liquidityOpts, false);
    }

    function test_openVault_InvalidCollarOptsDuration() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            minCashAmount: 100
        });

        ICollarVaultState.CollarOpts memory invalidlength =
            ICollarVaultState.CollarOpts({ duration: 99, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts = ICollarVaultState.LiquidityOpts({
            liquidityPool: address(pool),
            putStrikeTick: 90,
            callStrikeTick: 110
        });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);

        vm.expectRevert("invalid duration");
        manager.openVault(assets, invalidlength, liquidityOpts, false);
    }

    function test_openVault_InvalidCollarOptsLTV() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            minCashAmount: 100
        });

        ICollarVaultState.CollarOpts memory invalidlength =
            ICollarVaultState.CollarOpts({ duration: 100, ltv: 9001 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts = ICollarVaultState.LiquidityOpts({
            liquidityPool: address(pool),
            putStrikeTick: 90,
            callStrikeTick: 110
        });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);

        vm.expectRevert("invalid LTV");
        manager.openVault(assets, invalidlength, liquidityOpts, false);
    }

    function test_openVault_InvalidLiquidityOpts() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            minCashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts =
            ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory invalidPool = ICollarVaultState.LiquidityOpts({
            liquidityPool: address(collateralAsset),
            putStrikeTick: 90,
            callStrikeTick: 110
        });

        ICollarVaultState.LiquidityOpts memory invalidPutStrike = ICollarVaultState.LiquidityOpts({
            liquidityPool: address(pool),
            putStrikeTick: 90_000,
            callStrikeTick: 110
        });

        ICollarVaultState.LiquidityOpts memory invalidCallStrike = ICollarVaultState.LiquidityOpts({
            liquidityPool: address(pool),
            putStrikeTick: 90,
            callStrikeTick: 90
        });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);

        vm.expectRevert("invalid pool");
        manager.openVault(assets, collarOpts, invalidPool, false);

        vm.expectRevert("invalid put price");
        manager.openVault(assets, collarOpts, invalidPutStrike, false);

        vm.expectRevert("invalid call tick");
        manager.openVault(assets, collarOpts, invalidCallStrike, false);
    }

    function test_openVault_NotEnoughAssets() public {
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            minCashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts =
            ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts = ICollarVaultState.LiquidityOpts({
            liquidityPool: address(pool),
            putStrikeTick: 90,
            callStrikeTick: 110
        });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);

        collateralAsset.approve(address(pool), 100_000);
        collateralAsset.approve(address(manager), 100_000);

        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, address(user1), 0, 100));
        manager.openVault(assets, collarOpts, liquidityOpts, false);
    }

    function test_openVaultNotManagerOwner() public {
        mintTokensAddLiquidityAndOpenVault(false);
        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            minCashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts =
            ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts = ICollarVaultState.LiquidityOpts({
            liquidityPool: address(pool),
            putStrikeTick: 90,
            callStrikeTick: 110
        });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        hoax(user2);
        vm.expectRevert("not vault user");
        manager.openVault(assets, collarOpts, liquidityOpts, false);
    }

    function test_openVaultTradeNotViable() public {
        mintTokensAddLiquidityAndOpenVault(false);
        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            minCashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts =
            ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts = ICollarVaultState.LiquidityOpts({
            liquidityPool: address(badPool),
            putStrikeTick: 90,
            callStrikeTick: 110
        });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        hoax(user1);
        vm.expectRevert("slippage exceeded");
        badManager.openVault(assets, collarOpts, liquidityOpts, false);
    }

    function test_closeVaultNoPriceChange() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);

        skip(100);

        engine.setHistoricalAssetPrice(address(collateralAsset), 101, 1e18);

        manager.closeVault(uuid);

        // check vault info
        ICollarVaultState.Vault memory vault = manager.vaultInfo(uuid);

        assertEq(vault.active, false);
        assertEq(vault.openedAt, 1);
        assertEq(vault.expiresAt, 101);
        assertEq(vault.ltv, 9000);
        assertEq(vault.collateralAsset, address(collateralAsset));
        assertEq(vault.collateralAmount, 100);
        assertEq(vault.cashAsset, address(cashAsset));
        assertEq(vault.cashAmount, 100);
        assertEq(vault.liquidityPool, address(pool));
        assertEq(vault.lockedPoolCash, 10);
        assertEq(vault.initialCollateralPrice, 1e18);
        assertEq(vault.putStrikePrice, 0.9e18);
        assertEq(vault.callStrikePrice, 1.1e18);
        assertEq(vault.loanBalance, 90);
        assertEq(vault.lockedVaultCash, 0);

        // check to make sure that the pool got the free 10 cash tokens as a reward
        assertEq(cashAsset.balanceOf(address(manager)), 100);
    }

    function test_closeVaultNoCollateralPriceUp() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);

        skip(100);

        closeVaultUserWinsCase(user1, uuid, 101);

        // check vault info
        ICollarVaultState.Vault memory vault = manager.vaultInfo(uuid);
        assertEq(vault.active, false);
        assertEq(vault.openedAt, 1);
        assertEq(vault.expiresAt, 101);
        assertEq(vault.ltv, 9000);
        assertEq(vault.collateralAsset, address(collateralAsset));
        assertEq(vault.collateralAmount, 100);
        assertEq(vault.cashAsset, address(cashAsset));
        assertEq(vault.cashAmount, 100);
        assertEq(vault.liquidityPool, address(pool));
        assertEq(vault.lockedPoolCash, 10);
        assertEq(vault.initialCollateralPrice, 1e18);
        assertEq(vault.putStrikePrice, 0.9e18);
        assertEq(vault.callStrikePrice, 1.1e18);
        assertEq(vault.loanBalance, 90);
        assertEq(vault.lockedVaultCash, 0);

        // check to make sure that the vault got the free 10 cash tokens as a reward
        assertEq(cashAsset.balanceOf(address(manager)), 110);
    }

    function test_closeVaultInvalidPrice() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);
        skip(100);
        engine.setHistoricalAssetPrice(address(collateralAsset), 101, 0);
        vm.expectRevert("invalid price");
        hoax(user1);
        manager.closeVault(uuid);
    }

    function test_closeVaultPartialPriceDown() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);

        skip(100);

        closeVaultUserPartiallyLosesCase(user1, uuid, 101);

        // check to make sure that the user got the free 5 cash tokens as a reward
        assertEq(cashAsset.balanceOf(address(manager)), 95);
    }

    function test_closeVaultPartialPriceUp() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);

        skip(100);

        closeVaultUserPartiallyWinsCase(user1, uuid, 101);

        // check to make sure that the pool got the free 10 cash tokens as a reward
        assertEq(cashAsset.balanceOf(address(manager)), 105);
    }

    function test_closeVaultNoCollateralPriceDown() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);

        skip(100);

        closeVaultUserLosesCase(user1, uuid, 101);

        // check vault info
        ICollarVaultState.Vault memory vault = manager.vaultInfo(uuid);

        assertEq(vault.active, false);
        assertEq(vault.openedAt, 1);
        assertEq(vault.expiresAt, 101);
        assertEq(vault.ltv, 9000);
        assertEq(vault.collateralAsset, address(collateralAsset));
        assertEq(vault.collateralAmount, 100);
        assertEq(vault.cashAsset, address(cashAsset));
        assertEq(vault.cashAmount, 100);
        assertEq(vault.liquidityPool, address(pool));
        assertEq(vault.lockedPoolCash, 10);
        assertEq(vault.initialCollateralPrice, 1e18);
        assertEq(vault.putStrikePrice, 0.9e18);
        assertEq(vault.callStrikePrice, 1.1e18);
        assertEq(vault.loanBalance, 90);
        assertEq(vault.lockedVaultCash, 0);

        // check to make sure that the pool got the free 10 cash tokens as a reward
        assertEq(cashAsset.balanceOf(address(manager)), 90);
    }

    function test_closeVault_AlreadyClosed() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);

        skip(100);

        engine.setHistoricalAssetPrice(address(collateralAsset), 101, 1e18);

        manager.closeVault(uuid);

        vm.expectRevert("not active");
        manager.closeVault(uuid);
    }

    function test_closeVault_InvalidVault() public {
        vm.expectRevert("invalid vault");
        manager.closeVault(bytes32(0));
    }

    function test_closeVault_NotExpired() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);

        vm.expectRevert("not finalizable");
        manager.closeVault(uuid);

        // advance some blocks, but not all of them!
        skip(25);

        vm.expectRevert("not finalizable");
        manager.closeVault(uuid);
    }

    function test_redeem() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);

        ICollarVaultState.Vault memory vault = manager.vaultInfo(uuid);
        assertEq(vault.lockedVaultCash, 10);
        assertEq(vault.lockedPoolCash, 10);

        skip(100);

        closeVaultUserWinsCase(user1, uuid, 101);

        ERC6909TokenSupply token = ERC6909TokenSupply(manager);

        vault = manager.vaultInfo(uuid);

        assertEq(token.totalSupply(uint(uuid)), 100);
        assertEq(token.balanceOf(user1, uint(uuid)), 100);

        assertEq(manager.vaultTokenCashSupply(uuid), 20);

        assertEq(vault.lockedVaultCash, 0);

        uint toReceive = manager.previewRedeem(uuid, 100);
        assertEq(toReceive, 20);

        startHoax(user1);
        manager.redeem(uuid, 100);

        assertEq(cashAsset.balanceOf(user1), 100_020);
        assertEq(cashAsset.balanceOf(address(manager)), 90);

        vault = manager.vaultInfo(uuid);

        assertEq(vault.lockedVaultCash, 0);
        assertEq(vault.loanBalance, 90);
    }

    function test_redeem_InvalidVault() public {
        startHoax(user1);
        vm.expectRevert("invalid vault");
        manager.redeem(bytes32(0), 100);
    }

    function test_redeem_InvalidAmount() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);

        ICollarVaultState.Vault memory vault = manager.vaultInfo(uuid);

        assertEq(vault.lockedVaultCash, 10);
        assertEq(vault.lockedPoolCash, 10);

        skip(100);

        engine.setHistoricalAssetPrice(address(collateralAsset), vault.expiresAt, 2e18);

        startHoax(user1);
        manager.closeVault(uuid);

        vm.expectRevert("invalid amount");
        manager.redeem(uuid, 100_000 ether);
    }

    function test_redeem_NotFinalized() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);

        vm.expectRevert("vault not finalized");
        manager.redeem(uuid, 100);
    }

    function test_previewRedeem() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);
        ERC6909TokenSupply token = ERC6909TokenSupply(manager);
        ICollarVaultState.Vault memory vault = manager.vaultInfo(uuid);

        assertEq(vault.lockedVaultCash, 10);
        assertEq(vault.lockedPoolCash, 10);

        skip(100);
        closeVaultUserWinsCase(user1, uuid, 101);

        vault = manager.vaultInfo(uuid);

        assertEq(token.totalSupply(uint(uuid)), 100);
        assertEq(token.balanceOf(user1, uint(uuid)), 100);

        assertEq(manager.vaultTokenCashSupply(uuid), 20);

        assertEq(vault.lockedVaultCash, 0);

        uint toReceive = manager.previewRedeem(uuid, 100);
        assertEq(toReceive, 20);

        toReceive = manager.previewRedeem(uuid, 50);
        assertEq(toReceive, 10);
    }

    function test_previewRedeem_InvalidVault() public {
        vm.expectRevert("invalid vault");
        manager.previewRedeem(bytes32(0), 100);
    }

    function test_previewRedeem_InvalidAmount() public {
        vm.expectRevert("invalid amount");
        manager.previewRedeem(bytes32(0), 0);
    }

    function test_previewRedeem_Zero_Cash() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);
        skip(100);
        closeVaultUserLosesCase(user1, uuid, 101);
        hoax(user1);
        uint amountToRedeem = manager.previewRedeem(uuid, 100);
        assertEq(amountToRedeem, 0);
    }

    function test_previewRedeem_VaultNotFinalized() public {
        // Assuming there is a function to create a vault for testing purposes
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false); // Create a vault with some test data
        vm.expectRevert("vault not finalized");
        manager.previewRedeem(uuid, 1);
    }

    function test_withdraw() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);
        hoax(user1);
        manager.withdraw(uuid, 90);

        assertEq(cashAsset.balanceOf(user1), 100_090);
    }

    function test_withdraw_OnlyUser() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);

        vm.expectRevert("not vault user");
        manager.withdraw(uuid, 90);
    }

    function test_withdraw_TooMuch() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);

        vm.expectRevert("invalid amount");
        hoax(user1);
        manager.withdraw(uuid, 91);
    }

    function test_withdraw_InvalidVault() public {
        hoax(user1);
        vm.expectRevert("invalid vault");
        manager.withdraw(bytes32(0), 100);
    }

    function test_vaultInfo_InvalidVault() public view {
        ICollarVaultState.Vault memory vault = manager.vaultInfo(bytes32(0));
        assertEq(vault.expiresAt, 0);
    }

    function test_isVaultExpired() public {
        bytes32 uuid = mintTokensAddLiquidityAndOpenVault(false);

        bool isVaultExpired = manager.isVaultExpired(uuid);
        assertEq(isVaultExpired, false);

        skip(101);

        bool isVaultExpiredAfterTime = manager.isVaultExpired(uuid);
        assertEq(isVaultExpiredAfterTime, true);
    }

    function openVaultAsUser(address user, bool withdraw) internal returns (bytes32 uuid) {
        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            minCashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts =
            ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts = ICollarVaultState.LiquidityOpts({
            liquidityPool: address(pool),
            putStrikeTick: 90,
            callStrikeTick: 110
        });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        hoax(user);
        uuid = manager.openVault(assets, collarOpts, liquidityOpts, withdraw);
    }

    function addLiquidityToPoolAsUser(address user) internal {
        mintTokensToUserAndApprovePool(user);
        hoax(user);
        pool.addLiquidityToSlot(11_000, 25_000);
    }

    function mintTokensAddLiquidityAndOpenVault(bool withdraw) internal returns (bytes32 uuid) {
        mintTokensToUserAndApproveManager(user1);
        addLiquidityToPoolAsUser(user2);
        uuid = openVaultAsUser(user1, withdraw);
    }

    function closeVaultUserWinsCase(address user, bytes32 uuid, uint32 timestamp) internal {
        vm.startPrank(user);
        engine.setHistoricalAssetPrice(address(collateralAsset), timestamp, 2e18);
        manager.closeVault(uuid);
        vm.stopPrank();
    }

    function closeVaultUserLosesCase(address user, bytes32 uuid, uint32 timestamp) internal {
        engine.setHistoricalAssetPrice(address(collateralAsset), timestamp, 0.8e18);
        vm.startPrank(user);
        manager.closeVault(uuid);
        vm.stopPrank();
    }

    function closeVaultUserPartiallyLosesCase(address user, bytes32 uuid, uint32 timestamp) internal {
        engine.setHistoricalAssetPrice(address(collateralAsset), timestamp, 0.95e18);
        vm.startPrank(user);
        manager.closeVault(uuid);
        vm.stopPrank();
    }

    function closeVaultUserPartiallyWinsCase(address user, bytes32 uuid, uint32 timestamp) internal {
        engine.setHistoricalAssetPrice(address(collateralAsset), timestamp, 1.05e18);
        vm.startPrank(user);
        manager.closeVault(uuid);
        vm.stopPrank();
    }
}
