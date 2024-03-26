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

        pool = new CollarPool(address(engine), 1, address(token2), address(token1), 100, 9000);

        hoax(user1);
        manager = CollarVaultManager(engine.createVaultManager());

        engine.addLiquidityPool(address(pool));
        engine.addSupportedCollateralAsset(address(token1));
        engine.addSupportedCashAsset(address(token2));
        engine.addCollarDuration(100);

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
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        assertEq(manager.vaultCount(), 1);

        bytes memory vaultInfo = manager.vaultInfo(uuid);

        // grab the vault state & check all the values

        ICollarVaultState.Vault memory vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

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
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory invalidCollatAddr = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token2),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.AssetSpecifiers memory invalidCollatAmount = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 0,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.AssetSpecifiers memory invalidCashAmount = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 0
        });

        ICollarVaultState.AssetSpecifiers memory invalidCashAddr = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token1),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

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
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory invalidlength = ICollarVaultState.CollarOpts({ duration: 99, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        startHoax(user1);

        vm.expectRevert("Invalid length");
        manager.openVault(assets, invalidlength, liquidityOpts);
    }

    function test_openVault_InvalidLiquidityOpts() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory invalidPool =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(token1), putStrikeTick: 9000, callStrikeTick: 11_000 });

        ICollarVaultState.LiquidityOpts memory invalidPutStrike =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 900_000, callStrikeTick: 11_000 });

        ICollarVaultState.LiquidityOpts memory invalidCallStrike =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 110 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        hoax(user1);

        vm.expectRevert("Unsupported liquidity pool");
        manager.openVault(assets, collarOpts, invalidPool);
    }

    function test_openVault_NotEnoughAssets() public {
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

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
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        skip(100);

        engine.setHistoricalAssetPrice(address(token1), 101, 1e18);

        manager.closeVault(uuid);

        bytes memory vaultInfo = manager.vaultInfo(uuid);

        // check vault info
        ICollarVaultState.Vault memory vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

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
        assertEq(token2.balanceOf(address(manager)), 100);
    }

    function test_closeVaultNoCollateralPriceUp() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        skip(100);

        engine.setHistoricalAssetPrice(address(token1), 101, 2e18);

        manager.closeVault(uuid);

        bytes memory vaultInfo = manager.vaultInfo(uuid);

        // check vault info
        ICollarVaultState.Vault memory vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

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

        // check to make sure that the vault got the free 10 cash tokens as a reward
        assertEq(token2.balanceOf(address(manager)), 110);
    }

    function test_closeVaultNoCollateralPriceDown() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        skip(100);

        engine.setHistoricalAssetPrice(address(token1), 101, 1);

        manager.closeVault(uuid);

        bytes memory vaultInfo = manager.vaultInfo(uuid);

        // check vault info
        ICollarVaultState.Vault memory vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

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
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        skip(100);

        engine.setHistoricalAssetPrice(address(token1), 101, 1e18);

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
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

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
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        bytes memory vaultInfo = manager.vaultInfo(uuid);
        ICollarVaultState.Vault memory vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

        assertEq(vault.lockedVaultCash, 10);
        assertEq(vault.lockedPoolCash, 10);

        skip(100);

        engine.setHistoricalAssetPrice(address(token1), vault.expiresAt, 2e18);

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

        hoax(user1);
        manager.redeem(uuid, 100);

        assertEq(token2.balanceOf(user1), 100_020);
        assertEq(token2.balanceOf(address(manager)), 90);

        vaultInfo = manager.vaultInfo(uuid);
        vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

        assertEq(vault.lockedVaultCash, 0);
        assertEq(vault.loanBalance, 90);
    }

    function test_redeem_InvalidVault() public {
        vm.expectRevert("Vault does not exist");
        manager.redeem(bytes32(0), 100);
    }

    function test_redeem_InvalidAmount() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        bytes memory vaultInfo = manager.vaultInfo(uuid);
        ICollarVaultState.Vault memory vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

        assertEq(vault.lockedVaultCash, 10);
        assertEq(vault.lockedPoolCash, 10);

        skip(100);

        engine.setHistoricalAssetPrice(address(token1), vault.expiresAt, 2e18);

        startHoax(user1);
        manager.closeVault(uuid);

        vm.expectRevert("Amount cannot be 0");
        manager.redeem(uuid, 0);
    }

    function test_redeem_NotFinalized() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        startHoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        vm.expectRevert("Vault not finalized / still active!");
        manager.redeem(uuid, 100);
    }

    function test_previewRedeem() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        bytes memory vaultInfo = manager.vaultInfo(uuid);
        ICollarVaultState.Vault memory vault = abi.decode(vaultInfo, (ICollarVaultState.Vault));

        assertEq(vault.lockedVaultCash, 10);
        assertEq(vault.lockedPoolCash, 10);

        skip(100);

        engine.setHistoricalAssetPrice(address(token1), vault.expiresAt, 2e18);

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
        vm.expectRevert("Vault does not exist");
        manager.previewRedeem(bytes32(0), 100);
    }

    function test_previewRedeem_InvalidAmount() public {
        vm.expectRevert("Amount cannot be 0");
        manager.previewRedeem(bytes32(0), 0);
    }

    function test_withdraw() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        startHoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        manager.withdraw(uuid, 90);

        assertEq(token2.balanceOf(user1), 100_090);
    }

    function test_withdraw_OnlyUser() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        hoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        vm.expectRevert("Only user can withdraw");
        manager.withdraw(uuid, 90);
    }

    function test_withdraw_TooMuch() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        hoax(user2);
        pool.addLiquidityToSlot(11_000, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(token1),
            collateralAmount: 100,
            cashAsset: address(token2),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts = ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts =
            ICollarVaultState.LiquidityOpts({ liquidityPool: address(pool), putStrikeTick: 9000, callStrikeTick: 11_000 });

        engine.setCurrentAssetPrice(address(token1), 1e18);

        startHoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts);

        vm.expectRevert("Insufficient loan balance");
        manager.withdraw(uuid, 91);
    }

    function test_withdraw_InvalidVault() public {
        hoax(user1);
        vm.expectRevert("Vault does not exist");
        manager.withdraw(bytes32(0), 100);
    }

    function test_vaultInfo_InvalidVault() public {
        vm.expectRevert("Vault does not exist");
        manager.vaultInfo(bytes32(0));
    }
}
