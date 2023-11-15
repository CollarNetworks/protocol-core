// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import { LockableSubdividedLiquidityPool } from "../../../src/liquidity/implementations/LockableSubdividedLiquidityPool.sol";
import { LockableSubdividedLiquidityPoolErrors } from "../../../src/liquidity/interfaces/ILockableSubdividedLiquidityPool.sol";
import { TestERC20 } from "../../utils/TestERC20.sol";

contract LockableSubdividedLiquidityPoolTest is Test {
    LockableSubdividedLiquidityPool pool;
    TestERC20 asset;
    address other;

    function setUp() public {
        asset = new TestERC20("Test", "TST");
        pool = new LockableSubdividedLiquidityPool(address(asset));
        other = makeAddr("other");
    }

    function test_lockLiquidity() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        pool.depositToTick(address(this), 100, 100);
        pool.lockLiquidityAtTick(100, 100);

        assertEq(pool.lockedliquidityAtTick(100), 100);
        assertEq(pool.lockedliquidityAtTickByAddress(100, address(this)), 100);
    }

    function test_unlockLiquidity() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        pool.depositToTick(address(this), 100, 100);
        pool.lockLiquidityAtTick(100, 100);
        pool.unlockLiquidityAtTick(100, 100);

        assertEq(pool.lockedliquidityAtTick(100), 0);
        assertEq(pool.lockedliquidityAtTickByAddress(100, address(this)), 0);
    }

    function test_lockTooMuchLiquidity() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        pool.depositToTick(address(this), 100, 100);

        vm.expectRevert(LockableSubdividedLiquidityPoolErrors.InsufficientUnlockedBalance.selector);
        pool.lockLiquidityAtTick(101, 100);
    }

    function test_unlockTooMuchLiquidity() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        pool.depositToTick(address(this), 100, 100);
        pool.lockLiquidityAtTick(100, 100);

        vm.expectRevert(LockableSubdividedLiquidityPoolErrors.InsufficientLockedBalance.selector);
        pool.unlockLiquidityAtTick(101, 100);
    }

    function test_withdrawUnlockedLiquidity() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        pool.depositToTick(address(this), 100, 100);
        pool.lockLiquidityAtTick(100, 100);
        pool.unlockLiquidityAtTick(50, 100);

        pool.withdrawFromTick(address(this), 50, 100);

        assertEq(pool.liquidityAtTick(100), 50);
        assertEq(pool.liquidityAtTickByAddress(100, address(this)), 50);
        assertEq(pool.lockedliquidityAtTick(100), 50);
        assertEq(pool.lockedliquidityAtTickByAddress(100, address(this)), 50);
    }

    function test_withdrawLockedLiquidity() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        pool.depositToTick(address(this), 100, 100);
        pool.lockLiquidityAtTick(100, 100);
        
        vm.expectRevert(LockableSubdividedLiquidityPoolErrors.InsufficientUnlockedBalance.selector);
        pool.withdrawFromTick(address(this), 100, 100);
    }

    function test_lockLiquidityAtTicks() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        uint256[] memory amounts = new uint256[](2);

        amounts[0] = 100;
        amounts[1] = 200;

        uint24[] memory ticks = new uint24[](2);

        ticks[0] = 100;
        ticks[1] = 200;

        pool.depositToTicks(address(this), amounts, ticks);
        pool.lockLiquidityAtTicks(amounts, ticks);

        assertEq(pool.lockedliquidityAtTick(100), 100);
        assertEq(pool.lockedliquidityAtTickByAddress(100, address(this)), 100);

        assertEq(pool.lockedliquidityAtTick(200), 200);
        assertEq(pool.lockedliquidityAtTickByAddress(200, address(this)), 200);
    }

    function test_unlockLiquidityAtTicks() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        uint256[] memory amounts = new uint256[](2);

        amounts[0] = 100;
        amounts[1] = 200;

        uint24[] memory ticks = new uint24[](2);

        ticks[0] = 100;
        ticks[1] = 200;

        pool.depositToTicks(address(this), amounts, ticks);
        pool.lockLiquidityAtTicks(amounts, ticks);
        pool.unlockLiquidityAtTicks(amounts, ticks);

        assertEq(pool.lockedliquidityAtTick(100), 0);
        assertEq(pool.lockedliquidityAtTickByAddress(100, address(this)), 0);

        assertEq(pool.lockedliquidityAtTick(200), 0);
        assertEq(pool.lockedliquidityAtTickByAddress(200, address(this)), 0);
    }

    function test_withdrawUnlockedLiquidityMulti() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        uint256[] memory amounts = new uint256[](2);

        amounts[0] = 100;
        amounts[1] = 200;

        uint24[] memory ticks = new uint24[](2);

        ticks[0] = 100;
        ticks[1] = 200;

        pool.depositToTicks(address(this), amounts, ticks);
        pool.lockLiquidityAtTicks(amounts, ticks);
        pool.unlockLiquidityAtTicks(amounts, ticks);

        uint256[] memory withdrawAmounts = new uint256[](2);

        withdrawAmounts[0] = 100;
        withdrawAmounts[1] = 200;

        pool.withdrawFromTicks(address(this), withdrawAmounts, ticks);

        assertEq(pool.liquidityAtTick(100), 0);
        assertEq(pool.liquidityAtTickByAddress(100, address(this)), 0);

        assertEq(pool.liquidityAtTick(200), 0);
        assertEq(pool.liquidityAtTickByAddress(200, address(this)), 0);

        assertEq(pool.lockedliquidityAtTick(100), 0);
        assertEq(pool.lockedliquidityAtTickByAddress(100, address(this)), 0);

        assertEq(pool.lockedliquidityAtTick(200), 0);
        assertEq(pool.lockedliquidityAtTickByAddress(200, address(this)), 0);

        assertEq(asset.balanceOf(address(this)), 1000);
    }

    function test_withdrawLockedLiquidityMulti() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        uint256[] memory amounts = new uint256[](2);

        amounts[0] = 100;
        amounts[1] = 200;

        uint24[] memory ticks = new uint24[](2);

        ticks[0] = 100;
        ticks[1] = 200;

        pool.depositToTicks(address(this), amounts, ticks);
        pool.lockLiquidityAtTicks(amounts, ticks);

        uint256[] memory withdrawAmounts = new uint256[](2);

        withdrawAmounts[0] = 100;
        withdrawAmounts[1] = 200;

        vm.expectRevert(LockableSubdividedLiquidityPoolErrors.InsufficientUnlockedBalance.selector);
        pool.withdrawFromTicks(address(this), withdrawAmounts, ticks);
    }
}