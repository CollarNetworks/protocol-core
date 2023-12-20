// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { TestERC20 } from "../utils/TestERC20.sol";

contract CollarPoolTest is Test {
    TestERC20 token1;
    TestERC20 token2;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    // below we copy error messages from contracts since they aren't by default "public" or otherwise accessible

    error OwnableUnauthorizedAccount(address account);
    bytes user1NotAuthorized = abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(user1));

    function setUp() public {
        token1 = new TestERC20("Test1", "TST1");
        token2 = new TestERC20("Test2", "TST2");
    }

    function test_deploymentAndDeployParams() public {
        revert("TODO");
    }

    function test_addLiquidity() public {
        revert("TODO");
    }

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

    function test_removeLiquidity() public {
        revert("TODO");
    }

    function test_removeLiquidity_InvalidSlot() public {
        revert("TODO");
    }

    function test_removeLiquidity_AmountTooHigh() public {
        revert("TODO");
    }

    function test_reallocateLiquidity() public {
        revert("TODO");
    }

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