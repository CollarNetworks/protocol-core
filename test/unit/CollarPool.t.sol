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
import { CollarVaultManager } from "../../src/implementations/CollarVaultManager.sol";
import { CollarEngine } from "../../src/implementations/CollarEngine.sol";
import { ERC6909TokenSupply } from "@erc6909/ERC6909TokenSupply.sol";

contract CollarPoolTest is Test, ICollarPoolState {
    TestERC20 token1;
    TestERC20 token2;
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

        manager = new CollarVaultManager(address(engine), user1);

        engine.forceRegisterVaultManager(user1, address(manager));

        pool = new CollarPool(address(engine), 1, address(token1), address(token2), 100, 9_000);

        vm.label(address(token1), "Test Token 1 // Pool Cash Token");
        vm.label(address(token2), "Test Token 2 // Collateral");

        vm.label(address(pool), "CollarPool");
        vm.label(address(engine), "CollarEngine");
    }

    function mintTokensAndApprovePool(address recipient) internal {
        startHoax(recipient);
        token1.mint(recipient, 100_000);
        token2.mint(recipient, 100_000);
        token1.approve(address(pool), 100_000);
        token2.approve(address(pool), 100_000);
        vm.stopPrank();
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

    function test_addLiquidityToSlot() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidityToSlot(111, 25_000);

        assertEq(pool.getLiquidityForSlot(111), 25_000);
        assertEq(pool.getSlotProviderInfoForAddress(111, user1), 25_000);
        assertEq(pool.getNumProvidersInSlot(111), 1);

        (address provider0, uint256 liquidity0) = pool.getSlotProviderInfoAtIndex(111, 0);

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

        uint256[] memory slotIds = new uint256[](2);
        slotIds[0] = 111;
        slotIds[1] = 222;

        uint256[] memory liquidity = pool.getLiquidityForSlots(slotIds);

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

        uint256[] memory iSlots = pool.getInitializedSlotIndices();

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

        assertEq(iSlots.length, 1);
        assertEq(iSlots[0], 222);

        // remove liquidity from the other slot, and then query again, should return 0 slots
        hoax(user2);
        pool.withdrawLiquidityFromSlot(222, 2000);

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

        uint256 liquidity = pool.getLiquidityForSlot(111);
        uint256 providerLength = pool.getNumProvidersInSlot(111);

        assertEq(liquidity, 15_000);
        assertEq(providerLength, 5);

        (address provider0, uint256 liquidity0) = pool.getSlotProviderInfoAtIndex(111, 0);
        (address provider1, uint256 liquidity1) = pool.getSlotProviderInfoAtIndex(111, 1);
        (address provider2, uint256 liquidity2) = pool.getSlotProviderInfoAtIndex(111, 2);
        (address provider3, uint256 liquidity3) = pool.getSlotProviderInfoAtIndex(111, 3);
        (address provider4, uint256 liquidity4) = pool.getSlotProviderInfoAtIndex(111, 4);

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

    function test_addLiquidity_NotEnoughCash() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);
        token1.approve(address(pool), 1000e18);

        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientBalance.selector, address(user1), 100_000, 1e18));
        pool.addLiquidityToSlot(111, 1e18);
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
        vm.expectRevert("Amount not high enough to kick out anyone from full slot.");
        pool.addLiquidityToSlot(111, 500);
    }

    function test_removeLiquidityFromSlot() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidityToSlot(111, 25_000);
        pool.withdrawLiquidityFromSlot(111, 10_000);

        assertEq(pool.getLiquidityForSlot(111), 15_000);

        uint256 liquidity = pool.getLiquidityForSlot(111);
        uint256 providerLength = pool.getNumProvidersInSlot(111);

        assertEq(liquidity, 15_000);
        assertEq(providerLength, 1);

        (address provider0, uint256 liquidity0) = pool.getSlotProviderInfoAtIndex(111, 0);

        assertEq(provider0, user1);
        assertEq(liquidity0, 15_000);

        vm.stopPrank();
    }

    function test_removeLiquidity_InvalidSlot() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidityToSlot(111, 25_000);

        vm.expectRevert(abi.encodeWithSelector(EnumerableMapNonexistentKey.selector, user1));
        pool.withdrawLiquidityFromSlot(110, 10_000);
    }

    function test_removeLiquidity_AmountTooHigh() public {
        mintTokensToUserAndApprovePool(user1);

        startHoax(user1);

        pool.addLiquidityToSlot(111, 25_000);

        vm.expectRevert("Not enough liquidity");
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

        vm.expectRevert(abi.encodeWithSelector(EnumerableMapNonexistentKey.selector, user1));
        pool.getSlotProviderInfoForAddress(111, user1);

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

        vm.expectRevert("Not enough liquidity");
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

        vm.expectRevert("Amount not high enough to kick out anyone from full slot.");
        pool.moveLiquidityFromSlot(110, 111, 500);
    }

    function test_openPosition() public {
        mintTokensAndApprovePool(user1);
        mintTokensAndApprovePool(address(manager));

        startHoax(user1);
        pool.addLiquidityToSlot(111, 100_000);

        startHoax(address(manager));
        pool.openPosition(keccak256(abi.encodePacked(user1)), 111, 100_000, block.timestamp + 100);

        uint256 userTokens = ERC6909TokenSupply(address(pool)).balanceOf(user1, uint256(keccak256(abi.encodePacked(user1))));

        assertEq(userTokens, 100_000);
    }

    function test_openPosition_InvalidVault() public {
        mintTokensAndApprovePool(user1);
        mintTokensAndApprovePool(address(manager));

        startHoax(user1);

        pool.addLiquidityToSlot(111, 100_000);

        vm.expectRevert("Only registered vaults can mint");
        pool.openPosition(keccak256(abi.encodePacked(user1)), 111, 100_000, block.timestamp + 100);
    }

    function test_openPosition_InvalidSlot() public {
        mintTokensAndApprovePool(user1);
        mintTokensAndApprovePool(address(manager));

        startHoax(user1);
        pool.addLiquidityToSlot(111, 100_000);

        startHoax(address(manager));

        vm.expectRevert("No providers in slot");
        pool.openPosition(keccak256(abi.encodePacked(user1)), 112, 100_000, block.timestamp + 100);
    }

    function test_redeem() public {
        mintTokensAndApprovePool(user1);
        mintTokensAndApprovePool(address(manager));

        startHoax(user1);
        pool.addLiquidityToSlot(111, 100_000);

        startHoax(address(manager));
        pool.openPosition(keccak256(abi.encodePacked(user1)), 111, 100_000, block.timestamp + 100);

        ERC6909TokenSupply(address(pool)).balanceOf(user1, uint256(keccak256(abi.encodePacked(user1))));

        startHoax(user1);

        pool.redeem(keccak256(abi.encodePacked(user1)), 100_000);
    }

    function test_redeem_InvalidAmount() public {
        mintTokensAndApprovePool(user1);
        mintTokensAndApprovePool(address(manager));

        startHoax(user1);
        pool.addLiquidityToSlot(111, 100_000);

        startHoax(address(manager));
        pool.openPosition(keccak256(abi.encodePacked(user1)), 111, 100_000, block.timestamp + 100);

        ERC6909TokenSupply(address(pool)).balanceOf(user1, uint256(keccak256(abi.encodePacked(user1))));

        startHoax(user1);

        vm.expectRevert("Not enough tokens");
        pool.redeem(keccak256(abi.encodePacked(user1)), 110_000);
    }

    function test_redeem_VaultNotFinalized() public {
        mintTokensAndApprovePool(user1);
        mintTokensAndApprovePool(address(manager));

        startHoax(user1);
        pool.addLiquidityToSlot(111, 100_000);

        startHoax(address(manager));
        pool.openPosition(keccak256(abi.encodePacked(user1)), 111, 100_000, block.timestamp + 100);

        ERC6909TokenSupply(address(pool)).balanceOf(user1, uint256(keccak256(abi.encodePacked(user1))));

        startHoax(user1);

        vm.expectRevert("Vault not finalized or invalid");
        pool.redeem(keccak256(abi.encodePacked(user1)), 100_000);
    }

    function test_redeem_VaultNotValid() public {
        mintTokensAndApprovePool(user1);
        mintTokensAndApprovePool(address(manager));

        startHoax(user1);
        pool.addLiquidityToSlot(111, 100_000);

        startHoax(address(manager));
        pool.openPosition(keccak256(abi.encodePacked(user1)), 111, 100_000, block.timestamp + 100);

        ERC6909TokenSupply(address(pool)).balanceOf(user1, uint256(keccak256(abi.encodePacked(user1))));

        startHoax(user1);

        vm.expectRevert("Vault not finalized or invalid");
        pool.redeem(keccak256(abi.encodePacked(user2)), 100_000);
    }

    function test_previewRedeem() public {
        mintTokensAndApprovePool(user1);
        mintTokensAndApprovePool(address(manager));

        startHoax(user1);
        pool.addLiquidityToSlot(111, 100_000);

        startHoax(address(manager));
        pool.openPosition(keccak256(abi.encodePacked(user1)), 111, 100_000, block.timestamp + 100);

        ERC6909TokenSupply(address(pool)).balanceOf(user1, uint256(keccak256(abi.encodePacked(user1))));

        startHoax(user1);

        uint256 previewAmount = pool.previewRedeem(keccak256(abi.encodePacked(user1)), 100_000);

        assertEq(previewAmount, 100_000);
    }

    function test_previewRedeem_VaultNotValid() public {
        mintTokensAndApprovePool(user1);
        mintTokensAndApprovePool(address(manager));

        startHoax(user1);
        pool.addLiquidityToSlot(111, 100_000);

        startHoax(address(manager));
        pool.openPosition(keccak256(abi.encodePacked(user1)), 111, 100_000, block.timestamp + 100);

        ERC6909TokenSupply(address(pool)).balanceOf(user1, uint256(keccak256(abi.encodePacked(user1))));
    }

    function test_previewRedeem_InvalidAmount() public {
        mintTokensAndApprovePool(user1);
        mintTokensAndApprovePool(address(manager));

        startHoax(user1);
        pool.addLiquidityToSlot(111, 100_000);

        startHoax(address(manager));
        pool.openPosition(keccak256(abi.encodePacked(user1)), 111, 100_000, block.timestamp + 100);

        ERC6909TokenSupply(address(pool)).balanceOf(user1, uint256(keccak256(abi.encodePacked(user1))));

        startHoax(user1);

        /*uint256 previewAmount =*/
        pool.previewRedeem(keccak256(abi.encodePacked(user1)), 110_000);
    }
}
