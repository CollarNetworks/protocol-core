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

    // below we copy error messages from contracts since they aren't by default "public" or otherwise accessible

    error OwnableUnauthorizedAccount(address account);
    bytes user1NotAuthorized = abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(user1));

    function setUp() public {
        token1 = new TestERC20("Test1", "TST1");
        token2 = new TestERC20("Test2", "TST2");

        router = new MockUniRouter();
        engine = new CollarEngine(address(router));

        pool = new CollarPool(address(engine), 1, address(token1));

        startHoax(user1);
        token1.mint(user1, 100_000);
        token1.approve(address(pool), 100_000);
    }

    function test_deploymentAndDeployParams() public {
        assertEq(pool.engine(), address(engine));
        assertEq(pool.cashAsset(), address(token1));
        assertEq(pool.tickScaleFactor(), 1);
    }

    function test_addLiquidity() public {
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
    }

    function test_addLiquidity_FillEntireSlot() public {
        revert("TODO");
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