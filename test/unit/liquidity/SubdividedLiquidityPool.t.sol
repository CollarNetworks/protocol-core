// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import { SubdividedLiquidityPool } from "../../../src/liquidity/implementations/SubdividedLiquidityPool.sol";
import { SubdividedLiquidityPoolErrors } from "../../../src/liquidity/interfaces/ISubdividedLiquidityPool.sol";
import { SharedLiquidityPoolErrors } from "../../../src/liquidity/interfaces/ISharedLiquidityPool.sol";
import { TestERC20 } from "../../utils/TestERC20.sol";

contract LiquidityPoolTest is Test {
    SubdividedLiquidityPool pool;
    TestERC20 asset;
    address other;

    function setUp() public {
        asset = new TestERC20("Test", "TST");
        pool = new SubdividedLiquidityPool(address(asset), 1); // 0.01% per tick
        other = makeAddr("other");
    }

    function test_depositSingle() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        pool.deposit(address(this), 333, 0);
        pool.deposit(address(this), 333, 25);
        pool.deposit(address(this), 334, 0);

        uint256 balanceActual = asset.balanceOf(address(pool));
        uint256 balancedClaimed = pool.balance();

        assertEq(balanceActual, 1000);
        assertEq(balancedClaimed, 1000);

        assertEq(pool.liquidityAtTick(0), 667);
        assertEq(pool.liquidityAtTick(25), 333);

        assertEq(pool.liquidityAtTickByAddress(0, address(this)), 667);
        assertEq(pool.liquidityAtTickByAddress(25, address(this)), 333);

        assertEq(pool.balanceOf(address(this)), 1000);
    }

    function test_withdrawSingle() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        pool.deposit(address(this), 667, 0);
        pool.deposit(address(this), 333, 25);
        
        pool.withdraw(address(this), 333, 0);
        pool.withdraw(address(this), 333, 25);
        pool.withdraw(address(this), 334, 0);

        uint256 balanceActual = asset.balanceOf(address(pool));
        uint256 balancedClaimed = pool.balance();
        uint256 userBalance = pool.balanceOf(address(this));

        assertEq(balanceActual, 0);
        assertEq(balancedClaimed, 0);
        assertEq(userBalance, 0);

        assertEq(pool.liquidityAtTick(0), 0);
        assertEq(pool.liquidityAtTick(25), 0);

        assertEq(pool.liquidityAtTickByAddress(0, address(this)), 0);
        assertEq(pool.liquidityAtTickByAddress(25, address(this)), 0);

        assertEq(asset.balanceOf(address(this)), 1000);
    }

    function test_depositSingleNotEnoughAllowance() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 999);

        vm.expectRevert("ERC20: insufficient allowance");
        pool.deposit(address(this), 1000, 5);
    }

    function test_depositSingleNotEnoughBalance() public {
        asset.mint(address(this), 999);
        asset.approve(address(pool), 1000);

        pool.deposit(address(this), 1000, 5);
    }

    function test_depositNotEnoughAllowance() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 999);

        uint256 amount = 1000;
        uint24 tick = 1;

        vm.expectRevert("ERC20: insufficient allowance");
        pool.deposit(address(this), amount, tick);
    }

    function test_depositNotEnoughBalance() public {
        asset.mint(address(this), 999);
        asset.approve(address(pool), 1000);

        uint256 amount = 1000;
        uint24 tick = 1;

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        pool.deposit(address(this), amount, tick);
    }

    function test_depositSuper() public {
        vm.expectRevert(SubdividedLiquidityPoolErrors.NoGeneralDeposits.selector);
        pool.deposit(address(this), 1000);
    }

    function test_withdrawSuper() public {
        vm.expectRevert(SubdividedLiquidityPoolErrors.NoGeneralWithdrawals.selector);
        pool.withdraw(address(this), 1000);
    }
}