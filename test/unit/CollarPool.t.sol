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
import { CollarEngine } from "../../src/implementations/CollarEngine.sol";
import { CollarPool } from "../../src/implementations/CollarPool.sol";
import { ICollarPoolState } from "../../src/interfaces/ICollarPool.sol";

contract CollarPoolTest is Test, ICollarPoolState {
    TestERC20 token1;
    TestERC20 token2;
    MockUniRouter router;
    CollarEngine engine;
    CollarPool pool;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address user4 = makeAddr("user4");
    address user5 = makeAddr("user5");

    // below we copy error messages from contracts since they aren't by default "public" or otherwise accessible

    error OwnableUnauthorizedAccount(address account);
    bytes user1NotAuthorized = abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(user1));

    function setUp() public {
        token1 = new TestERC20("Test1", "TST1");
        token2 = new TestERC20("Test2", "TST2");

        router = new MockUniRouter();
        engine = new CollarEngine(address(router));

        pool = new CollarPool(address(engine), 1, address(token1));
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

        assertEq(pool.slotLiquidity(111), 25_000);
        assertEq(pool.providerLiquidityBySlot(user1, 111), 25_000);

        SlotState memory slot = pool.getSlot(111);

        assertEq(slot.liquidity, 25_000);
        assertEq(slot.providers.length, 5);
        assertEq(slot.providers[0], user1);
        assertEq(slot.amounts[0], 25_000);

        assertEq(slot.providers[1], address(0));
        assertEq(slot.providers[2], address(0));
        assertEq(slot.providers[3], address(0));
        assertEq(slot.providers[4], address(0));
    
        assertEq(slot.amounts[1], 0);
        assertEq(slot.amounts[2], 0);
        assertEq(slot.amounts[3], 0);
        assertEq(slot.amounts[4], 0);

        pool.addLiquidity(111, 100);

        assertEq(pool.slotLiquidity(111), 25_100);
        assertEq(pool.providerLiquidityBySlot(user1, 111), 25_100);

        slot = pool.getSlot(111);

        assertEq(slot.liquidity, 25_100);
        assertEq(slot.providers.length, 5);
        assertEq(slot.providers[0], user1);
        assertEq(slot.amounts[0], 25_100);

        vm.stopPrank();
    }

    function test_addLiquidity_FillEntireSlot() public {
        mintTokensToUserAndApprovePool(user1);
        mintTokensToUserAndApprovePool(user2);
        mintTokensToUserAndApprovePool(user3);
        mintTokensToUserAndApprovePool(user4);
        mintTokensToUserAndApprovePool(user5);

        hoax(user1);
        pool.addLiquidity(111, 1_000);

        hoax(user2);
        pool.addLiquidity(111, 2_000);

        hoax(user3);
        pool.addLiquidity(111, 3_000);

        hoax(user4);
        pool.addLiquidity(111, 4_000);

        hoax(user5);
        pool.addLiquidity(111, 5_000);

        assertEq(pool.slotLiquidity(111), 15_000);

        assertEq(pool.providerLiquidityBySlot(user1, 111), 1_000);
        assertEq(pool.providerLiquidityBySlot(user2, 111), 2_000);
        assertEq(pool.providerLiquidityBySlot(user3, 111), 3_000);
        assertEq(pool.providerLiquidityBySlot(user4, 111), 4_000);
        assertEq(pool.providerLiquidityBySlot(user5, 111), 5_000);

        SlotState memory slot = pool.getSlot(111);

        assertEq(slot.liquidity, 15_000);
        assertEq(slot.providers.length, 5);
        assertEq(slot.amounts.length, 5);

        assertEq(slot.providers[0], user1);
        assertEq(slot.providers[1], user2);
        assertEq(slot.providers[2], user3);
        assertEq(slot.providers[3], user4);
        assertEq(slot.providers[4], user5);

        assertEq(slot.amounts[0], 1_000);
        assertEq(slot.amounts[1], 2_000);
        assertEq(slot.amounts[2], 3_000);
        assertEq(slot.amounts[3], 4_000);
        assertEq(slot.amounts[4], 5_000);

        vm.stopPrank();
    }
    /*
    function test_addLiquidity_SlotFull() public {








        revert("TODO");
    }

    function test_addLiquidity_NotEnoughCash() public {

        revert("TODO");
    }

    function test_addLiquidity_InvalidSlot() public {



        revert("TODO");
    }

    function test_addLiquidity_SlotFullUserSmallestBidder() public {
 
        
        revert("TODO");
    }

    function test_addLiquidity_MinimumNotMet() public {



        revert("TODO");
    }

    */

    function test_removeLiquidity() public {
        startHoax(user1);

        pool.addLiquidity(111, 25_000);

        pool.removeLiquidity(111, 10_000);

        assertEq(pool.slotLiquidity(111), 15_000);

        SlotState memory slot = pool.getSlot(111);

        assertEq(slot.liquidity, 15_000);
        assertEq(slot.providers.length, 5);
        assertEq(slot.providers[0], user1);
        assertEq(slot.amounts[0], 15_000);

        assertEq(slot.providers[1], address(0));
        assertEq(slot.providers[2], address(0));
        assertEq(slot.providers[3], address(0));
        assertEq(slot.providers[4], address(0));
        assertEq(slot.amounts[1], 0);
        assertEq(slot.amounts[2], 0);
        assertEq(slot.amounts[3], 0);
        assertEq(slot.amounts[4], 0);

        vm.stopPrank();
    }

    /*
    function test_removeLiquidity_InvalidSlot() public {



        revert("TODO");
    }

    function test_removeLiquidity_AmountTooHigh() public {



        revert("TODO");
    }*/

    function test_reallocateLiquidity() public {



        revert("TODO");
    }

    /*
    function test_reallocateLiquidty_InvalidSource() public {



        revert("TODO");
    }

    function test_reallocateLiquidty_InvalidDestination() public {



        revert("TODO");
    }

    function test_reallocateLiquidty_SourceAmountTooHigh() public {



        revert("TODO");
    }

    function test_reallocateLiquidty_DestinationAmountTooHigh() public {



        revert("TODO");
    }

    function test_reallocateLiquidity_DestinationAmountMinimumNotMet() public {
        revert("TODO");
    }

    function test_reallocateLiquidity_DestinationFullUserSmallestBidder() public {
        revert("TODO");
    }

    */

    function test_vaultPullLiquidity() public {
        revert("TODO");
    }

    function test_vaultPullLiquidity_InvalidVault() public {
        revert("TODO");
    }

    function test_vaultPushLiquidity() public {
        revert("TODO");
    }

    function test_vaultPushLiquidity_InvalidAmount() public {
        revert("TODO");
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