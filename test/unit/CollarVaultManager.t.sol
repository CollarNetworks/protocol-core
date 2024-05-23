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
import { ICollarVaultState } from "../../src/interfaces/ICollarVaultState.sol";
import { ICollarVaultManager } from "../../src/interfaces/ICollarVaultManager.sol";
import { CollarVaultManager } from "../../src/implementations/CollarVaultManager.sol";
import { ERC6909TokenSupply } from "@erc6909/ERC6909TokenSupply.sol";
import { ICollarVaultManagerErrors } from "../../src/interfaces/errors/ICollarVaultManagerErrors.sol";
import { ICollarCommonErrors } from "../../src/interfaces/errors/ICollarCommonErrors.sol";

contract CollarVaultManagerTest is Test {
    TestERC20 cashAsset;
    TestERC20 collateralAsset;
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
        cashAsset = new TestERC20("Test1", "TST1");
        collateralAsset = new TestERC20("Test2", "TST2");

        router = new MockUniRouter();
        engine = new MockEngine(address(router), address(0xDEAD));

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
    }

    function mintTokensToUserAndApprovePool(address user) internal {
        startHoax(user);
        collateralAsset.mint(user, 100_000);
        cashAsset.mint(user, 100_000);
        collateralAsset.approve(address(pool), 100_000);
        cashAsset.approve(address(pool), 100_000);
        vm.stopPrank();
    }

    function mintTokensToUserAndApproveManager(address user) internal {
        startHoax(user);
        collateralAsset.mint(user, 100_000);
        cashAsset.mint(user, 100_000);
        collateralAsset.approve(address(manager), 100_000);
        cashAsset.approve(address(manager), 100_000);
        vm.stopPrank();
    }

    function test_getVaultUUID() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(110, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        hoax(user1);

        manager.openVault(assets, collarOpts, liquidityOpts, false);
        bytes32 calculatedUUID = keccak256(abi.encodePacked(user1, uint256(0)));

        assertEq(manager.vaultCount(), 1);
        assertEq(calculatedUUID, manager.vaultsByNonce(0));
    }

    function test_vaultInfoByNonce() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(110, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        hoax(user1);

        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        assertEq(manager.vaultCount(), 1);

        bytes memory vaultInfoViaUUID = manager.vaultInfo(uuid);
        bytes memory vaultInfoViaNonce = manager.vaultInfoByNonce(0);

        ICollarVaultState.Vault memory infoViaUUID = abi.decode(vaultInfoViaUUID, (ICollarVaultState.Vault));
        ICollarVaultState.Vault memory infoViaNonce = abi.decode(vaultInfoViaNonce, (ICollarVaultState.Vault));

        assertEq(infoViaUUID.expiresAt, infoViaNonce.expiresAt);
    }

    function test_deploymentAndDeployParams() public {
        assertEq(manager.owner(), user1);
        assertEq(manager.engine(), address(engine));
        assertEq(manager.vaultCount(), 0);
        assertEq(pool.tickScaleFactor(), 100);
    }

    function test_openVault() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(110, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        hoax(user1);
        manager.openVault(assets, collarOpts, liquidityOpts, false);

        bytes32 calculatedUUID = keccak256(abi.encodePacked(user1, uint256(0)));

        assertEq(manager.vaultCount(), 1);
        assertEq(manager.vaultsByNonce(0), calculatedUUID);

        bytes memory vaultInfo = manager.vaultInfo(calculatedUUID);

        // grab the vault state & check all the values

        ICollarVaultState.Vault memory vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

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
        mintTokensToUserAndApprovePool(user2);
        uint256 initialUserCashBalance = cashAsset.balanceOf(user1);
        console.log("Initial User Cash Balance: ", initialUserCashBalance);
        hoax(user2);
        pool.addLiquidityToSlot(110, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        hoax(user1);
        manager.openVault(assets, collarOpts, liquidityOpts, true);

        bytes32 calculatedUUID = keccak256(abi.encodePacked(user1, uint256(0)));

        assertEq(manager.vaultCount(), 1);
        assertEq(manager.vaultsByNonce(0), calculatedUUID);

        bytes memory vaultInfo = manager.vaultInfo(calculatedUUID);
        uint256 userCashBalance = cashAsset.balanceOf(user1);
        assertEq(userCashBalance, initialUserCashBalance + 90);
        // grab the vault state & check all the values
        ICollarVaultState.Vault memory vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));
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
            cashAmount: 100
        });

        ICollarVaultState.AssetSpecifiers memory invalidCollatAmount = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 0,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.AssetSpecifiers memory invalidCashAmount = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 0
        });

        ICollarVaultState.AssetSpecifiers memory invalidCashAddr = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(collateralAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);

        vm.expectRevert(ICollarCommonErrors.InvalidCollateralAsset.selector);
        manager.openVault(invalidCollatAddr, collarOpts, liquidityOpts, false);

        vm.expectRevert(ICollarCommonErrors.InvalidCollateralAmount.selector);
        manager.openVault(invalidCollatAmount, collarOpts, liquidityOpts, false);

        vm.expectRevert(ICollarCommonErrors.InvalidCashAsset.selector);
        manager.openVault(invalidCashAddr, collarOpts, liquidityOpts, false);

        vm.expectRevert(ICollarCommonErrors.InvalidCashAmount.selector);
        manager.openVault(invalidCashAmount, collarOpts, liquidityOpts, false);
    }

    function test_openVault_InvalidCollarOpts() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory invalidlength = ICollarVaultState.CollarOpts({ duration: 99, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);

        vm.expectRevert(ICollarCommonErrors.InvalidDuration.selector);
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
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory invalidPool =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(collateralAsset), putStrikeTick: 90, callStrikeTick: 110 });

        ICollarVaultState.LiquidityOpts memory invalidPutStrike =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90_000, callStrikeTick: 110 });

        ICollarVaultState.LiquidityOpts memory invalidCallStrike =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 90 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);

        vm.expectRevert(ICollarCommonErrors.InvalidLiquidityPool.selector);
        manager.openVault(assets, collarOpts, invalidPool, false);

        vm.expectRevert(ICollarVaultManagerErrors.InvalidPutStrike.selector);
        manager.openVault(assets, collarOpts, invalidPutStrike, false);

        vm.expectRevert(ICollarVaultManagerErrors.InvalidCallStrike.selector);
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
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);

        collateralAsset.approve(address(pool), 100_000);
        collateralAsset.approve(address(manager), 100_000);

        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, address(user1), 0, 100));
        manager.openVault(assets, collarOpts, liquidityOpts, false);
    }

    function test_closeVaultNoPriceChange() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        skip(100);

        engine.setHistoricalAssetPrice(address(collateralAsset), 101, 1e18);

        manager.closeVault(uuid);

        bytes memory vaultInfo = manager.vaultInfo(uuid);

        // check vault info
        ICollarVaultState.Vault memory vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

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
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        skip(100);

        engine.setHistoricalAssetPrice(address(collateralAsset), 101, 2e18);

        manager.closeVault(uuid);

        bytes memory vaultInfo = manager.vaultInfo(uuid);

        // check vault info
        ICollarVaultState.Vault memory vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

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

    function test_closeVaultNoCollateralPriceDown() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        skip(100);

        engine.setHistoricalAssetPrice(address(collateralAsset), 101, 1);

        manager.closeVault(uuid);

        bytes memory vaultInfo = manager.vaultInfo(uuid);

        // check vault info
        ICollarVaultState.Vault memory vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

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
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        skip(100);

        engine.setHistoricalAssetPrice(address(collateralAsset), 101, 1e18);

        manager.closeVault(uuid);

        vm.expectRevert(ICollarCommonErrors.VaultNotActive.selector);
        manager.closeVault(uuid);
    }

    function test_closeVault_InvalidVault() public {
        vm.expectRevert(ICollarCommonErrors.InvalidVault.selector);
        manager.closeVault(bytes32(0));
    }

    function test_closeVault_NotExpired() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(cashAsset), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        vm.expectRevert(ICollarCommonErrors.VaultNotFinalizable.selector);
        manager.closeVault(uuid);

        // advance some blocks, but not all of them!
        skip(25);

        vm.expectRevert(ICollarCommonErrors.VaultNotFinalizable.selector);
        manager.closeVault(uuid);
    }

    function test_redeem() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        startHoax(user2);
        pool.addLiquidityToSlot(110, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        bytes memory vaultInfo = manager.vaultInfo(uuid);
        ICollarVaultState.Vault memory vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

        assertEq(vault.lockedVaultCash, 10);
        assertEq(vault.lockedPoolCash, 10);

        skip(100);

        engine.setHistoricalAssetPrice(address(collateralAsset), vault.expiresAt, 2e18);

        manager.closeVault(uuid);

        ERC6909TokenSupply token = ERC6909TokenSupply(manager);

        vaultInfo = manager.vaultInfo(uuid);
        vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

        assertEq(token.totalSupply(uint256(uuid)), 100);
        assertEq(token.balanceOf(user1, uint256(uuid)), 100);

        assertEq(manager.vaultTokenCashSupply(uuid), 20);

        assertEq(vault.lockedVaultCash, 0);

        uint256 toReceive = manager.previewRedeem(uuid, 100);
        assertEq(toReceive, 20);

        startHoax(user1);
        manager.redeem(uuid, 100);

        assertEq(cashAsset.balanceOf(user1), 100_020);
        assertEq(cashAsset.balanceOf(address(manager)), 90);

        vaultInfo = manager.vaultInfo(uuid);
        vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

        assertEq(vault.lockedVaultCash, 0);
        assertEq(vault.loanBalance, 90);
    }

    function test_redeem_InvalidVault() public {
        startHoax(user1);
        vm.expectRevert(ICollarCommonErrors.InvalidVault.selector);
        manager.redeem(bytes32(0), 100);
    }

    function test_redeem_InvalidAmount() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        bytes memory vaultInfo = manager.vaultInfo(uuid);
        ICollarVaultState.Vault memory vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

        assertEq(vault.lockedVaultCash, 10);
        assertEq(vault.lockedPoolCash, 10);

        skip(100);

        engine.setHistoricalAssetPrice(address(collateralAsset), vault.expiresAt, 2e18);

        startHoax(user1);
        manager.closeVault(uuid);

        vm.expectRevert(ICollarCommonErrors.InvalidAmount.selector);
        manager.redeem(uuid, 100_000 ether);
    }

    function test_redeem_NotFinalized() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        vm.expectRevert(ICollarCommonErrors.VaultNotFinalized.selector);
        manager.redeem(uuid, 100);
    }

    function test_previewRedeem() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        bytes memory vaultInfo = manager.vaultInfo(uuid);
        ICollarVaultState.Vault memory vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

        assertEq(vault.lockedVaultCash, 10);
        assertEq(vault.lockedPoolCash, 10);

        skip(100);

        engine.setHistoricalAssetPrice(address(collateralAsset), vault.expiresAt, 2e18);

        manager.closeVault(uuid);

        ERC6909TokenSupply token = ERC6909TokenSupply(manager);

        vaultInfo = manager.vaultInfo(uuid);
        vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

        assertEq(token.totalSupply(uint256(uuid)), 100);
        assertEq(token.balanceOf(user1, uint256(uuid)), 100);

        assertEq(manager.vaultTokenCashSupply(uuid), 20);

        assertEq(vault.lockedVaultCash, 0);

        uint256 toReceive = manager.previewRedeem(uuid, 100);
        assertEq(toReceive, 20);

        toReceive = manager.previewRedeem(uuid, 50);
        assertEq(toReceive, 10);
    }

    function test_previewRedeem_InvalidVault() public {
        vm.expectRevert(ICollarCommonErrors.InvalidVault.selector);
        manager.previewRedeem(bytes32(0), 100);
    }

    function test_previewRedeem_InvalidAmount() public {
        vm.expectRevert(ICollarCommonErrors.AmountCannotBeZero.selector);
        manager.previewRedeem(bytes32(0), 0);
    }

    function test_withdraw() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        manager.withdraw(uuid, 90);

        assertEq(cashAsset.balanceOf(user1), 100_090);
    }

    function test_withdraw_OnlyUser() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        vm.expectRevert(ICollarCommonErrors.NotCollarVaultOwner.selector);
        manager.withdraw(uuid, 90);
    }

    function test_withdraw_TooMuch() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        vm.expectRevert(ICollarCommonErrors.InvalidAmount.selector);
        manager.withdraw(uuid, 91);
    }

    function test_withdraw_InvalidVault() public {
        hoax(user1);
        vm.expectRevert(ICollarCommonErrors.InvalidVault.selector);
        manager.withdraw(bytes32(0), 100);
    }

    function test_vaultInfo_InvalidVault() public {
        vm.expectRevert(ICollarCommonErrors.InvalidVault.selector);
        manager.vaultInfo(bytes32(0));
    }

    function test_isVaultExpired() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 90, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        bool isVaultExpired = manager.isVaultExpired(uuid);
        assertEq(isVaultExpired, false);

        skip(101);

        bool isVaultExpiredAfterTime = manager.isVaultExpired(uuid);
        assertEq(isVaultExpiredAfterTime, true);
    }
}
