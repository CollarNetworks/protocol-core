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
        pool = new LockableSubdividedLiquidityPool(address(asset), 1); // 0.01% per tick
        other = makeAddr("other");
    }

    function test_lock() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        uint256 amount0 = 100;
        uint256 amount1 = 200;

        uint24 tick0 = 100;
        uint24 tick1 = 200;

        pool.deposit(address(this), amount0, tick0);
        pool.deposit(address(this), amount1, tick1);

        pool.lock(amount0, tick0);
        pool.lock(amount1, tick1);

        assertEq(pool.lockedLiquidityAtTick(100), 100);
        assertEq(pool.lockedLiquidityAtTickByAddress(100, address(this)), 100);

        assertEq(pool.lockedLiquidityAtTick(200), 200);
        assertEq(pool.lockedLiquidityAtTickByAddress(200, address(this)), 200);
    }

    function test_unlock() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        uint256 amount0 = 100;
        uint256 amount1 = 200;

        uint24 tick0 = 100;
        uint24 tick1 = 200;

        pool.deposit(address(this), amount0, tick0);
        pool.deposit(address(this), amount1, tick1);

        pool.lock(amount0, tick0);
        pool.lock(amount1, tick1);
        
        pool.unlock(amount0, tick0);
        pool.unlock(amount1, tick1);

        assertEq(pool.lockedLiquidityAtTick(100), 0);
        //assertEq(pool.lockedLiquidityAtTickByAddress(100, address(this)), 0);
        // @todo re-enable once unlock logic figured out

        assertEq(pool.lockedLiquidityAtTick(200), 0);
        //assertEq(pool.lockedLiquidityAtTickByAddress(200, address(this)), 0);
        // @todo re-enable once unlock logic figured out
    }

    function test_lockTooMuchLiquidity() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        pool.deposit(address(this), 100, 100);

        vm.expectRevert(LockableSubdividedLiquidityPoolErrors.InsufficientUnlockedBalance.selector);
        pool.lock(101, 100);
    }

    function test_unlockTooMuchLiquidity() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        pool.deposit(address(this), 100, 100);
        pool.lock(100, 100);

        vm.expectRevert(LockableSubdividedLiquidityPoolErrors.InsufficientLockedBalance.selector);
        pool.unlock(101, 100);
    }

    /*
    function test_withdrawUnlockedLiquidity() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        pool.deposit(address(this), 100, 100);
        pool.lock(100, 100);
        pool.unlock(50, 100);

        pool.withdraw(address(this), 50, 100);

        assertEq(pool.liquidityAtTick(100), 50);
        assertEq(pool.liquidityAtTickByAddress(100, address(this)), 50);
        assertEq(pool.lockedLiquidityAtTick(100), 50);
        assertEq(pool.lockedLiquidityAtTickByAddress(100, address(this)), 50);

        // @todo re-examine this test after unlock logic figured out
    }
    */

    function test_withdrawlockedLiquidity() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        pool.deposit(address(this), 100, 100);
        pool.lock(100, 100);
        
        vm.expectRevert(LockableSubdividedLiquidityPoolErrors.InsufficientUnlockedBalance.selector);
        pool.withdraw(address(this), 100, 100);
    }
}