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

contract CollarPoolTest is Test, ICollarPoolState {
    TestERC20 token1;
    TestERC20 token2;
    MockUniRouter router;
    MockEngine engine;
    CollarPool pool;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address user4 = makeAddr("user4");
    address user5 = makeAddr("user5");
    address user6 = makeAddr("user6");

    // below we copy error messages from contracts since they aren't by default "public" or otherwise accessible

    error EnumerableMapNonexistentKey(bytes32 key);
    error OwnableUnauthorizedAccount(address account);
    error ERC20InsufficientBalance(address account, uint256 amount, uint256 balance);

    bytes user1NotAuthorized = abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(user1));

    function setUp() public {
        token1 = new TestERC20("Test1", "TST1");
        token2 = new TestERC20("Test2", "TST2");

        router = new MockUniRouter();
        engine = new MockEngine(address(router));

        pool = new CollarPool(address(engine), 1, address(token1));

        vm.label(address(token1), "Test Token 1 // Pool Cash Token");
        vm.label(address(token2), "Test Token 2 // Collateral");

        vm.label(address(pool), "CollarPool");
        vm.label(address(engine), "CollarEngine");
    }

    function mintTokensToUserAndApprovePool(address user) internal {
        startHoax(user);
        token1.mint(user, 100_000);
        token2.mint(user, 100_000);
        token1.approve(address(pool), 100_000);
        token2.approve(address(pool), 100_000);
        vm.stopPrank();
    }

    function test_deploymentAndDeployParams() public {
        assertEq(pool.engine(), address(engine));
        assertEq(pool.cashAsset(), address(token1));
        assertEq(pool.tickScaleFactor(), 1);
    }

    function test_addLiquidity() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidity(111, 25_000);

        assertEq(pool.getSlotLiquidity(111), 25_000);
        assertEq(pool.getSlotProviderInfo(111, user1), 25_000);
        assertEq(pool.getSlotProviderLength(111), 1);

        (address provider0, uint256 liquidity0) = pool.getSlotProviderInfoAt(111, 0);

        assertEq(provider0, user1);
        assertEq(liquidity0, 25_000);

        pool.addLiquidity(111, 100);

        assertEq(pool.getSlotLiquidity(111), 25_100);
        assertEq(pool.getSlotProviderInfo(111, user1), 25_100);

        vm.stopPrank();
    }

    function test_addLiquidity_FillEntireSlot() public {
        mintTokensToUserAndApprovePool(user1);
        mintTokensToUserAndApprovePool(user2);
        mintTokensToUserAndApprovePool(user3);
        mintTokensToUserAndApprovePool(user4);
        mintTokensToUserAndApprovePool(user5);

        hoax(user1);
        pool.addLiquidity(111, 1000);

        hoax(user2);
        pool.addLiquidity(111, 2000);

        hoax(user3);
        pool.addLiquidity(111, 3000);

        hoax(user4);
        pool.addLiquidity(111, 4000);

        hoax(user5);
        pool.addLiquidity(111, 5000);

        assertEq(pool.getSlotLiquidity(111), 15_000);

        assertEq(pool.getSlotProviderInfo(111, user1), 1000);
        assertEq(pool.getSlotProviderInfo(111, user2), 2000);
        assertEq(pool.getSlotProviderInfo(111, user3), 3000);
        assertEq(pool.getSlotProviderInfo(111, user4), 4000);
        assertEq(pool.getSlotProviderInfo(111, user5), 5000);

        uint256 liquidity = pool.getSlotLiquidity(111);
        uint256 providerLength = pool.getSlotProviderLength(111);

        assertEq(liquidity, 15_000);
        assertEq(providerLength, 5);

        (address provider0, uint256 liquidity0) = pool.getSlotProviderInfoAt(111, 0);
        (address provider1, uint256 liquidity1) = pool.getSlotProviderInfoAt(111, 1);
        (address provider2, uint256 liquidity2) = pool.getSlotProviderInfoAt(111, 2);
        (address provider3, uint256 liquidity3) = pool.getSlotProviderInfoAt(111, 3);
        (address provider4, uint256 liquidity4) = pool.getSlotProviderInfoAt(111, 4);

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
        pool.addLiquidity(111, 1000);

        hoax(user2);
        pool.addLiquidity(111, 2000);

        hoax(user3);
        pool.addLiquidity(111, 3000);

        hoax(user4);
        pool.addLiquidity(111, 4000);

        hoax(user5);
        pool.addLiquidity(111, 5000);

        hoax(user6);
        pool.addLiquidity(111, 6000);

        assertEq(pool.getSlotLiquidity(111), 20_000);
        assertEq(pool.getSlotProviderLength(111), 5);

        vm.expectRevert(abi.encodeWithSelector(EnumerableMapNonexistentKey.selector, user1));
        pool.getSlotProviderInfo(111, user1);

        assertEq(pool.getSlotProviderInfo(111, user2), 2000);
        assertEq(pool.getSlotProviderInfo(111, user3), 3000);
        assertEq(pool.getSlotProviderInfo(111, user4), 4000);
        assertEq(pool.getSlotProviderInfo(111, user5), 5000);
        assertEq(pool.getSlotProviderInfo(111, user6), 6000);

        assertEq(pool.getSlotLiquidity(pool.UNALLOCATED_SLOT()), 1000);
        assertEq(pool.getSlotProviderInfo(pool.UNALLOCATED_SLOT(), user1), 1000);
    }

    function test_addLiquidity_NotEnoughCash() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);
        token1.approve(address(pool), 1000e18);

        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, address(user1), 100_000, 1e18));
        pool.addLiquidity(111, 1e18);
    }

    function test_addLiquidity_InvalidSlot() public {
        revert("TODO: Add in gating below 100% for valid slots to add liquidity to");
    }

    function test_addLiquidity_SlotFullUserSmallestBidder() public {
        mintTokensToUserAndApprovePool(user1);
        mintTokensToUserAndApprovePool(user2);
        mintTokensToUserAndApprovePool(user3);
        mintTokensToUserAndApprovePool(user4);
        mintTokensToUserAndApprovePool(user5);
        mintTokensToUserAndApprovePool(user6);

        hoax(user1);
        pool.addLiquidity(111, 1000);

        hoax(user2);
        pool.addLiquidity(111, 2000);

        hoax(user3);
        pool.addLiquidity(111, 3000);

        hoax(user4);
        pool.addLiquidity(111, 4000);

        hoax(user5);
        pool.addLiquidity(111, 5000);

        hoax(user6);
        vm.expectRevert("Amount not high enough to kick out anyone from full slot.");
        pool.addLiquidity(111, 500);
    }

    function test_removeLiquidity() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidity(111, 25_000);
        pool.removeLiquidity(111, 10_000);

        assertEq(pool.getSlotLiquidity(111), 15_000);

        uint256 liquidity = pool.getSlotLiquidity(111);
        uint256 providerLength = pool.getSlotProviderLength(111);

        assertEq(liquidity, 15_000);
        assertEq(providerLength, 1);

        (address provider0, uint256 liquidity0) = pool.getSlotProviderInfoAt(111, 0);

        assertEq(provider0, user1);
        assertEq(liquidity0, 15_000);

        vm.stopPrank();
    }

    function test_removeLiquidity_InvalidSlot() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidity(111, 25_000);

        vm.expectRevert(abi.encodeWithSelector(EnumerableMapNonexistentKey.selector, user1));
        pool.removeLiquidity(110, 10_000);
    }

    function test_removeLiquidity_AmountTooHigh() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidity(111, 25_000);

        vm.expectRevert("Not enough liquidity");
        pool.removeLiquidity(111, 26_000);
    }

    function test_reallocateLiquidity() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidity(111, 25_000);
        pool.reallocateLiquidity(111, 222, 10_000);

        assertEq(pool.getSlotLiquidity(111), 15_000);
        assertEq(pool.getSlotLiquidity(222), 10_000);

        assertEq(pool.getSlotProviderInfo(111, user1), 15_000);
        assertEq(pool.getSlotProviderInfo(222, user1), 10_000);

        pool.reallocateLiquidity(111, 222, 15_000);

        assertEq(pool.getSlotLiquidity(111), 0);
        assertEq(pool.getSlotLiquidity(222), 25_000);

        vm.expectRevert(abi.encodeWithSelector(EnumerableMapNonexistentKey.selector, user1));
        pool.getSlotProviderInfo(111, user1);

        assertEq(pool.getSlotProviderInfo(222, user1), 25_000);
    }

    function test_reallocateLiquidty_InvalidSource() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidity(111, 25_000);

        vm.expectRevert(abi.encodeWithSelector(EnumerableMapNonexistentKey.selector, user1));
        pool.reallocateLiquidity(110, 222, 10_000);
    }

    function test_reallocateLiquidty_InvalidDestination() public {
        revert("TODO: Add in bounds checking for callstrikes in pools");

        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidity(111, 25_000);
        pool.reallocateLiquidity(111, 23, 10_000);
    }

    function test_reallocateLiquidty_DestinationAmountTooHigh() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidity(111, 25_000);

        vm.expectRevert("Not enough liquidity");
        pool.reallocateLiquidity(111, 23, 26_000);
    }

    function test_reallocateLiquidity_DestinationFullUserSmallestBidder() public {
        mintTokensToUserAndApprovePool(user1);
        mintTokensToUserAndApprovePool(user2);
        mintTokensToUserAndApprovePool(user3);
        mintTokensToUserAndApprovePool(user4);
        mintTokensToUserAndApprovePool(user5);
        mintTokensToUserAndApprovePool(user6);

        hoax(user1);
        pool.addLiquidity(111, 1000);

        hoax(user2);
        pool.addLiquidity(111, 2000);

        hoax(user3);
        pool.addLiquidity(111, 3000);

        hoax(user4);
        pool.addLiquidity(111, 4000);

        hoax(user5);
        pool.addLiquidity(111, 5000);

        startHoax(user6);

        pool.addLiquidity(110, 500);

        vm.expectRevert("Amount not high enough to kick out anyone from full slot.");
        pool.reallocateLiquidity(110, 111, 500);
    }

    function test_vaultPullLiquidity() public {
        revert("TODO");
    }

    function test_vaultPullLiquidity_Auth() public {
        revert("TODO: Add in auth checks for vault via engine passthru");
    }

    function test_vaultPushLiquidity_Auth() public {
        revert("TODO: Add in auth checks for vault via engine passthru");
    }

    function test_vaultPushLiquidity() public {
        revert("TODO");
    }

    function test_vaultPushLiquidity_InvalidAmount() public {
        vm.expectRevert("Cannot push 0 amount of liquidity");
        pool.vaultPushLiquidity(bytes32(0), user1, 0);
    }

    function test_vaultPullLiquidity_InvalidAmount() public {
        vm.expectRevert("Cannot push 0 amount of liquidity");
        pool.vaultPullLiquidity(bytes32(0), user1, 0);
    }

    function test_mint() public {
        revert("TODO");
    }

    function test_mint_InvalidVault() public {
        revert("TODO");
    }

    function test_mint_InvalidSlot() public {
        revert("TODO");
    }

    function test_redeem() public {
        revert("TODO");
    }

    function test_redeem_InvalidAmount() public {
        revert("TODO");
    }

    function test_redeem_VaultNotFinalized() public {
        revert("TODO");
    }

    function test_redeem_VaultNotValid() public {
        revert("TODO");
    }

    function test_previewRedeem() public {
        revert("TODO");
    }

    function test_previewRedeem_VaultNotFinalized() public {
        revert("TODO");
    }

    function test_previewRedeem_VaultNotValid() public {
        revert("TODO");
    }

    function test_previewRedeem_InvalidAmount() public {
        revert("TODO");
    }

    function test_finalizeVault() public {
        revert("TODO");
    }

    function test_finalizeVault_InvalidVault() public {
        revert("TODO");
    }

    function test_finalizeVault_NotYetExpired() public {
        revert("TODO");
    }

    function test_finalizeVault_AlreadyFinalized() public {
        revert("TODO");
    }
}
