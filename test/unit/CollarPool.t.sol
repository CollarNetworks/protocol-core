// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockUniRouter } from "../utils/MockUniRouter.sol";
import { MockEngine } from "../../test/utils/MockEngine.sol";
import { CollarPool } from "../../src/implementations/CollarPool.sol";
import { CollarVaultManager } from "../../src/implementations/CollarVaultManager.sol";
import { CollarEngine } from "../../src/implementations/CollarEngine.sol";
import { ERC6909TokenSupply } from "@erc6909/ERC6909TokenSupply.sol";
import { ICollarVaultState } from "../../src/interfaces/ICollarVaultState.sol";

contract CollarPoolTest is Test {
    TestERC20 cashAsset;
    TestERC20 collateralAsset;
    MockUniRouter router;
    MockEngine engine;
    CollarPool pool;
    CollarVaultManager manager;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address user4 = makeAddr("user4");
    address user5 = makeAddr("user5");
    address user6 = makeAddr("user6");

    // below we copy error messages from contracts since they aren't by default "public" or otherwise
    // accessible

    error EnumerableMapNonexistentKey(bytes32 key);
    error OwnableUnauthorizedAccount(address account);
    error ERC20InsufficientBalance(address account, uint amount, uint balance);

    bytes user1NotAuthorized = abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(user1));

    function setUp() public {
        cashAsset = new TestERC20("Test1", "TST1");
        collateralAsset = new TestERC20("Test2", "TST2");

        router = new MockUniRouter();
        engine = new MockEngine(address(router));

        cashAsset.mint(address(router), 100_000 ether);
        collateralAsset.mint(address(router), 100_000 ether);

        manager = new CollarVaultManager(address(engine), user1);

        engine.forceRegisterVaultManager(user1, address(manager));
        engine.addLTV(9000);

        engine.addSupportedCashAsset(address(cashAsset));
        engine.addSupportedCollateralAsset(address(collateralAsset));

        engine.addCollarDuration(100);

        pool = new CollarPool(address(engine), 100, address(cashAsset), address(collateralAsset), 100, 9000);

        engine.addLiquidityPool(address(pool));

        vm.label(address(cashAsset), "Test Token 1 // Pool Cash Token");
        vm.label(address(collateralAsset), "Test Token 2 // Collateral");

        vm.label(address(pool), "CollarPool");
        vm.label(address(engine), "CollarEngine");
    }

    function mintTokensAndApprovePool(address recipient) public {
        startHoax(recipient);
        cashAsset.mint(recipient, 100_000 ether);
        collateralAsset.mint(recipient, 100_000 ether);
        cashAsset.approve(address(pool), 100_000 ether);
        collateralAsset.approve(address(pool), 100_000 ether);
        vm.stopPrank();
    }

    function mintTokensToUserAndApprovePool(address user) public {
        startHoax(user);
        cashAsset.mint(user, 100_000 ether);
        collateralAsset.mint(user, 100_000 ether);
        cashAsset.approve(address(pool), 100_000 ether);
        collateralAsset.approve(address(pool), 100_000 ether);
        vm.stopPrank();
    }

    function mintTokensToUserAndApproveManager(address user) public {
        startHoax(user);
        cashAsset.mint(user, 100_000 ether);
        collateralAsset.mint(user, 100_000 ether);
        cashAsset.approve(address(manager), 100_000 ether);
        collateralAsset.approve(address(manager), 100_000 ether);
        vm.stopPrank();
    }

    function test_deploymentAndDeployParams() public {
        assertEq(pool.engine(), address(engine));
        assertEq(pool.cashAsset(), address(cashAsset));
        assertEq(pool.tickScaleFactor(), 100);
    }

    function test_addLiquidityToSlot() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidityToSlot(111, 25_000);

        assertEq(pool.getLiquidityForSlot(111), 25_000);
        assertEq(pool.getSlotProviderInfoForAddress(111, user1), 25_000);
        assertEq(pool.getNumProvidersInSlot(111), 1);

        (address provider0, uint liquidity0) = pool.getSlotProviderInfoAtIndex(111, 0);

        assertEq(provider0, user1);
        assertEq(liquidity0, 25_000);

        pool.addLiquidityToSlot(111, 100);

        assertEq(pool.getLiquidityForSlot(111), 25_100);
        assertEq(pool.getSlotProviderInfoForAddress(111, user1), 25_100);

        vm.stopPrank();
    }

    function test_getLiquidityForSlots() public {
        mintTokensToUserAndApprovePool(user1);

        // add liquidity to 2 slots and check the plural slots liquidity function
        startHoax(user1);

        pool.addLiquidityToSlot(111, 25_000);
        pool.addLiquidityToSlot(222, 50_000);

        uint[] memory slotIds = new uint[](2);
        slotIds[0] = 111;
        slotIds[1] = 222;

        uint[] memory liquidity = pool.getLiquidityForSlots(slotIds);

        assertEq(liquidity[0], 25_000);
        assertEq(liquidity[1], 50_000);

        assertEq(liquidity.length, 2);
    }

    function test_getInitializedSlotIndices() public {
        mintTokensToUserAndApprovePool(user1);
        mintTokensToUserAndApprovePool(user2);

        // grab the active liquidity slots in the pool - should be empty
        assertEq(pool.totalLiquidity(), 0);
        assertEq(pool.getInitializedSlotIndices().length, 0);

        // add liquidity, and then grab again - should have 1 slot
        hoax(user1);
        pool.addLiquidityToSlot(111, 1000);

        uint[] memory iSlots = pool.getInitializedSlotIndices();

        assertEq(iSlots.length, 1);
        assertEq(iSlots[0], 111);

        // add liquidity to another slot, and then grab again, should return 2 slots
        hoax(user2);
        pool.addLiquidityToSlot(222, 2000);

        iSlots = pool.getInitializedSlotIndices();

        assertEq(iSlots.length, 2);
        assertEq(iSlots[0], 111);
        assertEq(iSlots[1], 222);

        // remove liquidity from one slot, and then query again, should return 1 slot
        hoax(user1);
        pool.withdrawLiquidityFromSlot(111, 1000);
        iSlots = pool.getInitializedSlotIndices();

        // length get reduced by 1 (all liquidity from slot 111 gets removed )
        assertEq(iSlots.length, 1);
        assertEq(iSlots[0], 222);

        // remove liquidity from the other slot, and then query again, should return no slots
        hoax(user2);
        pool.withdrawLiquidityFromSlot(222, 2000);

        // length stays the same
        iSlots = pool.getInitializedSlotIndices();
        assertEq(iSlots.length, 0);
    }

    function test_addLiquidity_FillEntireSlot() public {
        mintTokensToUserAndApprovePool(user1);
        mintTokensToUserAndApprovePool(user2);
        mintTokensToUserAndApprovePool(user3);
        mintTokensToUserAndApprovePool(user4);
        mintTokensToUserAndApprovePool(user5);

        hoax(user1);
        pool.addLiquidityToSlot(111, 1000);

        hoax(user2);
        pool.addLiquidityToSlot(111, 2000);

        hoax(user3);
        pool.addLiquidityToSlot(111, 3000);

        hoax(user4);
        pool.addLiquidityToSlot(111, 4000);

        hoax(user5);
        pool.addLiquidityToSlot(111, 5000);

        assertEq(pool.getLiquidityForSlot(111), 15_000);

        assertEq(pool.getSlotProviderInfoForAddress(111, user1), 1000);
        assertEq(pool.getSlotProviderInfoForAddress(111, user2), 2000);
        assertEq(pool.getSlotProviderInfoForAddress(111, user3), 3000);
        assertEq(pool.getSlotProviderInfoForAddress(111, user4), 4000);
        assertEq(pool.getSlotProviderInfoForAddress(111, user5), 5000);

        uint liquidity = pool.getLiquidityForSlot(111);
        uint providerLength = pool.getNumProvidersInSlot(111);

        assertEq(liquidity, 15_000);
        assertEq(providerLength, 5);

        (address provider0, uint liquidity0) = pool.getSlotProviderInfoAtIndex(111, 0);
        (address provider1, uint liquidity1) = pool.getSlotProviderInfoAtIndex(111, 1);
        (address provider2, uint liquidity2) = pool.getSlotProviderInfoAtIndex(111, 2);
        (address provider3, uint liquidity3) = pool.getSlotProviderInfoAtIndex(111, 3);
        (address provider4, uint liquidity4) = pool.getSlotProviderInfoAtIndex(111, 4);

        assertEq(provider0, user1);
        assertEq(provider1, user2);
        assertEq(provider2, user3);
        assertEq(provider3, user4);
        assertEq(provider4, user5);

        assertEq(liquidity0, 1000);
        assertEq(liquidity1, 2000);
        assertEq(liquidity2, 3000);
        assertEq(liquidity3, 4000);
        assertEq(liquidity4, 5000);
    }

    function test_addLiquidity_SlotFull() public {
        mintTokensToUserAndApprovePool(user1);
        mintTokensToUserAndApprovePool(user2);
        mintTokensToUserAndApprovePool(user3);
        mintTokensToUserAndApprovePool(user4);
        mintTokensToUserAndApprovePool(user5);
        mintTokensToUserAndApprovePool(user6);

        hoax(user1);
        pool.addLiquidityToSlot(111, 1000);

        hoax(user2);
        pool.addLiquidityToSlot(111, 2000);

        hoax(user3);
        pool.addLiquidityToSlot(111, 3000);

        hoax(user4);
        pool.addLiquidityToSlot(111, 4000);

        hoax(user5);
        pool.addLiquidityToSlot(111, 5000);

        hoax(user6);
        pool.addLiquidityToSlot(111, 6000);

        assertEq(pool.getLiquidityForSlot(111), 20_000);
        assertEq(pool.getNumProvidersInSlot(111), 5);

        vm.expectRevert(abi.encodeWithSelector(EnumerableMapNonexistentKey.selector, user1));
        pool.getSlotProviderInfoForAddress(111, user1);

        assertEq(pool.getSlotProviderInfoForAddress(111, user2), 2000);
        assertEq(pool.getSlotProviderInfoForAddress(111, user3), 3000);
        assertEq(pool.getSlotProviderInfoForAddress(111, user4), 4000);
        assertEq(pool.getSlotProviderInfoForAddress(111, user5), 5000);
        assertEq(pool.getSlotProviderInfoForAddress(111, user6), 6000);

        assertEq(pool.getLiquidityForSlot(pool.UNALLOCATED_SLOT()), 1000);
        assertEq(pool.getSlotProviderInfoForAddress(pool.UNALLOCATED_SLOT(), user1), 1000);
    }

    function test_addLiquidity_SlotFullUserSmallestBidder() public {
        mintTokensToUserAndApprovePool(user1);
        mintTokensToUserAndApprovePool(user2);
        mintTokensToUserAndApprovePool(user3);
        mintTokensToUserAndApprovePool(user4);
        mintTokensToUserAndApprovePool(user5);
        mintTokensToUserAndApprovePool(user6);

        hoax(user1);
        pool.addLiquidityToSlot(111, 1000);

        hoax(user2);
        pool.addLiquidityToSlot(111, 2000);

        hoax(user3);
        pool.addLiquidityToSlot(111, 3000);

        hoax(user4);
        pool.addLiquidityToSlot(111, 4000);

        hoax(user5);
        pool.addLiquidityToSlot(111, 5000);

        hoax(user6);
        vm.expectRevert("no smaller slot available");
        pool.addLiquidityToSlot(111, 500);
    }

    function test_withdrawLiquidityFromSlot() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidityToSlot(111, 25_000);
        pool.withdrawLiquidityFromSlot(111, 10_000);
        assertEq(pool.getLiquidityForSlot(111), 15_000);

        uint liquidity = pool.getLiquidityForSlot(111);
        uint providerLength = pool.getNumProvidersInSlot(111);

        assertEq(liquidity, 15_000);
        assertEq(providerLength, 1);

        (address provider0, uint liquidity0) = pool.getSlotProviderInfoAtIndex(111, 0);

        assertEq(provider0, user1);
        assertEq(liquidity0, 15_000);

        vm.stopPrank();
    }

    function test_withdrawLiquidity_InvalidSlot() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        vm.expectRevert(abi.encodeWithSelector(EnumerableMapNonexistentKey.selector, user1));
        pool.withdrawLiquidityFromSlot(110, 10_000);
    }

    function test_removeLiquidity_AmountTooHigh() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidityToSlot(111, 25_000);

        vm.expectRevert("amount too large");
        pool.withdrawLiquidityFromSlot(111, 26_000);
    }

    function test_moveLiquidityFromSlot() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidityToSlot(111, 25_000);
        pool.moveLiquidityFromSlot(111, 222, 10_000);

        assertEq(pool.getLiquidityForSlot(111), 15_000);
        assertEq(pool.getLiquidityForSlot(222), 10_000);

        assertEq(pool.getSlotProviderInfoForAddress(111, user1), 15_000);
        assertEq(pool.getSlotProviderInfoForAddress(222, user1), 10_000);

        pool.moveLiquidityFromSlot(111, 222, 15_000);

        assertEq(pool.getLiquidityForSlot(111), 0);
        assertEq(pool.getLiquidityForSlot(222), 25_000);

        assertEq(pool.getSlotProviderInfoForAddress(222, user1), 25_000);
    }

    function test_reallocateLiquidty_InvalidSource() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidityToSlot(111, 25_000);

        vm.expectRevert(abi.encodeWithSelector(EnumerableMapNonexistentKey.selector, user1));
        pool.moveLiquidityFromSlot(110, 222, 10_000);
    }

    function test_reallocateLiquidty_DestinationAmountTooHigh() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidityToSlot(111, 25_000);

        vm.expectRevert("amount too large");
        pool.moveLiquidityFromSlot(111, 23, 26_000);
    }

    function test_reallocateLiquidity_DestinationFullUserSmallestBidder() public {
        mintTokensToUserAndApprovePool(user1);
        mintTokensToUserAndApprovePool(user2);
        mintTokensToUserAndApprovePool(user3);
        mintTokensToUserAndApprovePool(user4);
        mintTokensToUserAndApprovePool(user5);
        mintTokensToUserAndApprovePool(user6);

        hoax(user1);
        pool.addLiquidityToSlot(111, 1000);

        hoax(user2);
        pool.addLiquidityToSlot(111, 2000);

        hoax(user3);
        pool.addLiquidityToSlot(111, 3000);

        hoax(user4);
        pool.addLiquidityToSlot(111, 4000);

        hoax(user5);
        pool.addLiquidityToSlot(111, 5000);

        startHoax(user6);

        pool.addLiquidityToSlot(110, 500);

        vm.expectRevert("no smaller slot available");
        pool.moveLiquidityFromSlot(110, 111, 500);
    }

    function test_openPosition() public {
        mintAndOpenPosition(user1);

        uint userTokens =
            ERC6909TokenSupply(address(pool)).balanceOf(user1, uint(keccak256(abi.encodePacked(user1))));

        assertEq(userTokens, 100_000);
    }

    function test_openPosition_InvalidVault() public {
        mintTokensAndAddLiquidity(user1);

        vm.expectRevert("caller not vault");

        pool.openPosition(keccak256(abi.encodePacked(user1)), 111, 100_000, block.timestamp + 100);
    }

    function test_openPosition_InvalidSlot() public {
        mintTokensAndAddLiquidity(user1);

        startHoax(address(manager));

        vm.expectRevert("no providers");
        pool.openPosition(keccak256(abi.encodePacked(user1)), 112, 100_000, block.timestamp + 100);
    }

    function test_openPosition_InvalidSlotLiquidityAmount() public {
        mintTokensAndAddLiquidity(user1);

        startHoax(address(manager));

        vm.expectRevert("insufficient liquidity");
        pool.openPosition(keccak256(abi.encodePacked(user1)), 111, 100_001, block.timestamp + 100);
    }

    function test_finalizePositionNotVaultManager() public {
        mintTokensAndApprovePool(user2);
        mintAndOpenPosition(user1);

        ERC6909TokenSupply(address(pool)).balanceOf(user1, uint(keccak256(abi.encodePacked(user1))));

        startHoax(user1);
        vm.expectRevert("caller not vault");
        pool.finalizePosition(keccak256(abi.encodePacked(user1)), 100);
    }

    function test_redeem_normal() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        startHoax(user2);
        pool.addLiquidityToSlot(110, 25_000);

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

        // price starts at "1e18"
        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        ICollarVaultState.Vault memory vault = manager.vaultInfo(uuid);

        assertEq(vault.lockedVaultCash, 10);
        assertEq(vault.lockedPoolCash, 10);

        skip(100);

        // price closes at 50% of start
        engine.setHistoricalAssetPrice(address(collateralAsset), vault.expiresAt, 0.5e18);

        manager.closeVault(uuid);

        ERC6909TokenSupply token = ERC6909TokenSupply(pool);

        assertEq(token.totalSupply(uint(uuid)), 10);
        assertEq(token.balanceOf(user2, uint(uuid)), 10);

        startHoax(user2);
        uint toReceive = pool.previewRedeem(uuid, 10);
        assertEq(toReceive, 20);
        pool.redeem(uuid, 10);

        assertEq(cashAsset.balanceOf(user1), 100_000e18);
    }

    function test_redeem_InvalidAmount() public {
        mintAndOpenPosition(user1);
        ERC6909TokenSupply(address(pool)).balanceOf(user1, uint(keccak256(abi.encodePacked(user1))));
        // forward time:
        skip(101);
        startHoax(user1);

        vm.expectRevert("insufficient balance");
        pool.redeem(keccak256(abi.encodePacked(user1)), 110_000);
    }

    function test_redeem_VaultNotFinalized() public {
        mintAndOpenPosition(user1);

        ERC6909TokenSupply(address(pool)).balanceOf(user1, uint(keccak256(abi.encodePacked(user1))));

        startHoax(user1);

        vm.expectRevert("vault not finalized");
        pool.redeem(keccak256(abi.encodePacked(user1)), 100_000);
    }

    function test_redeem_VaultNotValid() public {
        mintAndOpenPosition(user1);

        ERC6909TokenSupply(address(pool)).balanceOf(user1, uint(keccak256(abi.encodePacked(user1))));
        // forward time:
        skip(101);
        startHoax(user1);

        vm.expectRevert("no position");
        pool.redeem(keccak256(abi.encodePacked(user2)), 100_000);
    }

    function test_redeem_PositionNotFinalized() public {
        mintAndOpenPosition(user1);

        ERC6909TokenSupply(address(pool)).balanceOf(user1, uint(keccak256(abi.encodePacked(user1))));
        // forward time:
        skip(101);
        startHoax(user1);

        vm.expectRevert("position not finalized");
        pool.redeem(keccak256(abi.encodePacked(user1)), 100_000);
    }

    function test_previewRedeem_same_person() public {
        mintTokensAndApprovePool(user1);
        mintTokensAndApprovePool(user2);
        mintTokensAndApprovePool(address(manager));

        hoax(user1);

        pool.addLiquidityToSlot(110, 100_000);

        hoax(address(manager));

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);

        (bytes32 uuid, ICollarVaultState.Vault memory vault) = setPriceAndOpenVault();

        skip(101);

        engine.setHistoricalAssetPrice(address(collateralAsset), vault.expiresAt, 0.5e18);

        manager.closeVault(uuid);

        uint previewAmount = pool.previewRedeem(uuid, 10);

        assertEq(previewAmount, 20);
    }

    function test_previewRedeem_different_people() public {
        mintTokensAndApprovePool(user1);
        mintTokensAndApprovePool(user2);
        mintTokensAndApprovePool(address(manager));

        hoax(user2);

        pool.addLiquidityToSlot(110, 100_000);

        hoax(address(manager));

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);

        (bytes32 uuid, ICollarVaultState.Vault memory vault) = setPriceAndOpenVault();

        startHoax(user2);

        skip(101);

        engine.setHistoricalAssetPrice(address(collateralAsset), vault.expiresAt, 0.5e18);

        manager.closeVault(uuid);

        uint previewAmount = pool.previewRedeem(uuid, 10);

        assertEq(previewAmount, 20);
    }

    function test_previewRedeem_VaultNotValid() public {
        mintAndOpenPosition(user1);

        ERC6909TokenSupply(address(pool)).balanceOf(user1, uint(keccak256(abi.encodePacked(user1))));
    }

    function test_previewRedeem_InvalidAmount() public {
        mintTokensAndApprovePool(user1);
        mintTokensAndApprovePool(user2);
        mintTokensAndApprovePool(address(manager));

        hoax(user1);

        pool.addLiquidityToSlot(110, 100_000);

        hoax(address(manager));

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);

        (bytes32 uuid, ICollarVaultState.Vault memory vault) = setPriceAndOpenVault();

        skip(101);

        engine.setHistoricalAssetPrice(address(collateralAsset), vault.expiresAt, 0.5e18);

        manager.closeVault(uuid);

        vm.expectRevert("insufficient balance");
        pool.previewRedeem(uuid, 11);
    }

    function test_constructor() public {
        // validation
        vm.expectRevert("invalid LTV");
        new CollarPool(address(engine), 100, address(cashAsset), address(collateralAsset), 0, 0);
        // happy case
        CollarPool testPool =
            new CollarPool(address(engine), 100, address(cashAsset), address(collateralAsset), 100, 9000);
        assertEq(testPool.engine(), address(engine));
        assertEq(testPool.cashAsset(), address(cashAsset));
        assertEq(testPool.collateralAsset(), address(collateralAsset));
        assertEq(testPool.duration(), 100);
        assertEq(testPool.ltv(), 9000);
    }

    function mintTokensForUser(address user) internal {
        mintTokensAndApprovePool(user);
        mintTokensAndApprovePool(address(manager));
    }

    function mintTokensAndAddLiquidity(address user) internal {
        mintTokensForUser(user);
        startHoax(user);
        pool.addLiquidityToSlot(111, 100_000);
    }

    function mintAndOpenPosition(address user) internal {
        mintTokensForUser(user);

        startHoax(user);
        pool.addLiquidityToSlot(111, 100_000);

        startHoax(address(manager));
        pool.openPosition(keccak256(abi.encodePacked(user)), 111, 100_000, block.timestamp + 100);
    }

    function setPriceAndOpenVault() internal returns (bytes32 uuid, ICollarVaultState.Vault memory vault) {
        collateralAsset.approve(address(manager), 100_000 ether);

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

        uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        vault = manager.vaultInfo(uuid);
    }
}
