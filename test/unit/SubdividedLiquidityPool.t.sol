// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import "../../src/liquidity/implementations/SubdividedLiquidityPool.sol";
import { TestERC20 } from "../utils/TestERC20.sol";

contract LiquidityPoolTest is Test {
    SubdividedLiquidityPool pool;
    TestERC20 asset;
    address other;

    function setUp() public {
        asset = new TestERC20("Test", "TST");
        pool = new SubdividedLiquidityPool(address(asset));
        other = makeAddr("other");
    }

    function test_depositSingle() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        pool.depositToTick(address(this), 333, 0);
        pool.depositToTick(address(this), 333, 25);
        pool.depositToTick(address(this), 334, 0);

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

        pool.depositToTick(address(this), 667, 0);
        pool.depositToTick(address(this), 333, 25);
        
        pool.withdrawFromTick(address(this), 333, 0);
        pool.withdrawFromTick(address(this), 333, 25);
        pool.withdrawFromTick(address(this), 334, 0);

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

    function test_depositPlural() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        uint256[] memory amounts = new uint256[](3);

        amounts[0] = 100;
        amounts[1] = 300;
        amounts[2] = 600;

        uint24[] memory ticks = new uint24[](3);

        ticks[0] = 1;
        ticks[1] = 25;
        ticks[2] = 10001;

        pool.depositToTicks(address(this), amounts, ticks);

        uint256 balanceActual = asset.balanceOf(address(pool));
        uint256 balancedClaimed = pool.balance();
        uint256 userBalance = pool.balanceOf(address(this));

        assertEq(balanceActual, 1000);
        assertEq(balancedClaimed, 1000);
        assertEq(userBalance, 1000);

        assertEq(pool.liquidityAtTick(1), 100);
        assertEq(pool.liquidityAtTick(25), 300);
        assertEq(pool.liquidityAtTick(10001), 600);

        assertEq(pool.liquidityAtTickByAddress(1, address(this)), 100);
        assertEq(pool.liquidityAtTickByAddress(25, address(this)), 300);
        assertEq(pool.liquidityAtTickByAddress(10001, address(this)), 600);
    }

    function test_withdrawPlural() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        uint256[] memory amounts = new uint256[](3);

        amounts[0] = 100;
        amounts[1] = 300;
        amounts[2] = 600;

        uint24[] memory ticks = new uint24[](3);

        ticks[0] = 1;
        ticks[1] = 25;
        ticks[2] = 10001;

        pool.depositToTicks(address(this), amounts, ticks);
        pool.withdrawFromTicks(address(this), amounts, ticks);

        uint256 balanceActual = asset.balanceOf(address(pool));
        uint256 balancedClaimed = pool.balance();
        uint256 userBalance = pool.balanceOf(address(this));

        assertEq(balanceActual, 0);
        assertEq(balancedClaimed, 0);
        assertEq(userBalance, 0);

        assertEq(pool.liquidityAtTick(1), 0);
        assertEq(pool.liquidityAtTick(25), 0);
        assertEq(pool.liquidityAtTick(10001), 0);

        assertEq(pool.liquidityAtTickByAddress(1, address(this)), 0);
        assertEq(pool.liquidityAtTickByAddress(25, address(this)), 0);
        assertEq(pool.liquidityAtTickByAddress(10001, address(this)), 0);
    }

    function test_depositPluralFromOther() public {
        asset.mint(other, 1000);
        asset.approve(address(pool), 1000);

        uint256[] memory amounts = new uint256[](3);

        amounts[0] = 100;
        amounts[1] = 300;
        amounts[2] = 600;

        uint24[] memory ticks = new uint24[](3);

        ticks[0] = 1;
        ticks[1] = 25;
        ticks[2] = 10001;

        startHoax(other);
            asset.approve(address(this), 1000);
            asset.approve(address(pool), 1000);
        vm.stopPrank();

        pool.depositToTicks(other, amounts, ticks);

        uint256 balanceActual = asset.balanceOf(address(pool));
        uint256 balancedClaimed = pool.balance();
        uint256 userBalance = pool.balanceOf(address(this));

        assertEq(balanceActual, 1000);
        assertEq(balancedClaimed, 1000);
        assertEq(userBalance, 1000);

        assertEq(pool.liquidityAtTick(1), 100);
        assertEq(pool.liquidityAtTick(25), 300);
        assertEq(pool.liquidityAtTick(10001), 600);

        assertEq(pool.liquidityAtTickByAddress(1, address(this)), 100);
        assertEq(pool.liquidityAtTickByAddress(25, address(this)), 300);
        assertEq(pool.liquidityAtTickByAddress(10001, address(this)), 600);
    }

    function test_withdrawPluralToOther() public {
        asset.mint(other, 1000);
        asset.approve(address(pool), 1000);

        uint256[] memory amounts = new uint256[](3);

        amounts[0] = 100;
        amounts[1] = 300;
        amounts[2] = 600;

        uint24[] memory ticks = new uint24[](3);

        ticks[0] = 1;
        ticks[1] = 25;
        ticks[2] = 10001;

        startHoax(other);
            asset.approve(address(this), 1000);
            asset.approve(address(pool), 1000);
        vm.stopPrank();

        pool.depositToTicks(other, amounts, ticks);
        pool.withdrawFromTicks(other, amounts, ticks);

        uint256 balanceActual = asset.balanceOf(address(pool));
        uint256 balancedClaimed = pool.balance();
        uint256 userBalance = pool.balanceOf(other);

        assertEq(balanceActual, 0);
        assertEq(balancedClaimed, 0);
        assertEq(userBalance, 0);

        assertEq(pool.liquidityAtTick(1), 0);
        assertEq(pool.liquidityAtTick(25), 0);
        assertEq(pool.liquidityAtTick(10001), 0);

        assertEq(pool.liquidityAtTickByAddress(1, address(this)), 0);
        assertEq(pool.liquidityAtTickByAddress(25, address(this)), 0);
        assertEq(pool.liquidityAtTickByAddress(10001, address(this)), 0);

        uint256 otherBalance = asset.balanceOf(other);
        assertEq(otherBalance, 1000);
    }

    function test_depositSingleNotEnoughAllowance() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 999);

        vm.expectRevert("ERC20: insufficient allowance");
        pool.depositToTick(address(this), 1000, 5);
    }

    function test_depositSingleNotEnoughBalance() public {
        asset.mint(address(this), 999);
        asset.approve(address(pool), 1000);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        pool.depositToTick(address(this), 1000, 5);
    }

    function test_depositPluralNotEnoughAllowance() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 999);

        uint256[] memory amounts = new uint256[](3);

        amounts[0] = 100;
        amounts[1] = 300;
        amounts[2] = 600;

        uint24[] memory ticks = new uint24[](3);

        ticks[0] = 1;
        ticks[1] = 25;
        ticks[2] = 10001;

        vm.expectRevert("ERC20: insufficient allowance");
        pool.depositToTicks(address(this), amounts, ticks);
    }

    function test_depositPluralNotEnoughBalance() public {
        asset.mint(address(this), 999);
        asset.approve(address(pool), 1000);

        uint256[] memory amounts = new uint256[](3);

        amounts[0] = 100;
        amounts[1] = 300;
        amounts[2] = 600;

        uint24[] memory ticks = new uint24[](3);

        ticks[0] = 1;
        ticks[1] = 25;
        ticks[2] = 10001;

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        pool.depositToTicks(address(this), amounts, ticks);
    }

    function test_withdrawPluralSomeTicksUnderflow() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        uint256[] memory amounts = new uint256[](3);

        amounts[0] = 100;
        amounts[1] = 300;
        amounts[2] = 600;

        uint24[] memory ticks = new uint24[](3);

        ticks[0] = 1;
        ticks[1] = 25;
        ticks[2] = 10001;

        pool.depositToTicks(address(this), amounts, ticks);

        amounts[2] = 601;

        vm.expectRevert(InsufficientBalance.selector);
        pool.withdrawFromTicks(address(this), amounts, ticks);
    }

    function test_depositPluralMismatchedArrays() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        uint256[] memory amounts = new uint256[](3);

        amounts[0] = 100;
        amounts[1] = 300;
        amounts[2] = 600;

        uint24[] memory ticksTooSmall = new uint24[](2);

        ticksTooSmall[0] = 1;
        ticksTooSmall[1] = 25;

        uint24[] memory ticksTooBig = new uint24[](4);

        ticksTooBig[0] = 1;
        ticksTooBig[1] = 25;
        ticksTooBig[2] = 10001;
        ticksTooBig[3] = 10002;

        vm.expectRevert(MismatchedArrays.selector);
        pool.depositToTicks(address(this), amounts, ticksTooSmall);

        vm.expectRevert(MismatchedArrays.selector);
        pool.depositToTicks(address(this), amounts, ticksTooBig);
    }

    function test_withdrawPluralMismatchedArrays() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);

        uint256[] memory amountsTooSmall = new uint256[](2);

        amountsTooSmall[0] = 100;
        amountsTooSmall[1] = 300;

        uint24[] memory ticks = new uint24[](3);

        ticks[0] = 1;
        ticks[1] = 25;
        ticks[2] = 10001;

        vm.expectRevert(MismatchedArrays.selector);
        pool.withdrawFromTicks(address(this), amountsTooSmall, ticks);
    }

    function test_depositSuper() public {
        vm.expectRevert(NoGeneralDeposits.selector);
        pool.deposit(address(this), 1000);
    }

    function test_withdrawSuper() public {
        vm.expectRevert(NoGeneralWithdrawals.selector);
        pool.withdraw(address(this), 1000);
    }
}