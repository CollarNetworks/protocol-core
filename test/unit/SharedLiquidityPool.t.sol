// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import { SharedLiquidityPool } from "../../src/liquidity/implementations/SharedLiquidityPool.sol";
import { SharedLiquidityPoolErrors } from "../../src/liquidity/interfaces/ISharedLiquidityPool.sol"; 
import { TestERC20 } from "../utils/TestERC20.sol";

contract SharedLiquidityPoolTest is Test {
    SharedLiquidityPool pool;
    TestERC20 asset;
    address other;

    function setUp() public {
        asset = new TestERC20("Test", "TST");
        pool = new SharedLiquidityPool(address(asset));
        other = makeAddr("other");
    }

    function test_deposit() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.deposit(address(this), 1000);

        uint256 balanceActual = asset.balanceOf(address(pool));
        uint256 balancedClaimed = pool.balance();
        uint256 userBalance = pool.balanceOf(address(this));

        assertEq(balanceActual, 1000);
        assertEq(balancedClaimed, 1000);
        assertEq(userBalance, 1000);
    }

    function test_depositFromOther() public {
        asset.mint(other, 1000);
        
        startHoax(other);
            asset.approve(address(this), 1000);
            asset.approve(address(pool), 1000);
        vm.stopPrank();

        pool.deposit(other, 1000);
    }

    function test_withdraw() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.deposit(address(this), 1000);

        pool.withdraw(address(this), 1000);

        uint256 balanceActual = asset.balanceOf(address(pool));
        uint256 balancedClaimed = pool.balance();
        uint256 userBalance = pool.balanceOf(address(this));
        uint256 userERC20Balance = asset.balanceOf(address(this));

        assertEq(balanceActual, 0);
        assertEq(balancedClaimed, 0);
        assertEq(userBalance, 0);
        assertEq(userERC20Balance, 1000);
    }

    function test_withdrawToOther() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.deposit(address(this), 1000);

        pool.withdraw(other, 1000);

        uint256 balanceActual = asset.balanceOf(address(pool));
        uint256 balancedClaimed = pool.balance();
        uint256 otherBalance = pool.balanceOf(other);
        uint256 otherERC20Balance = asset.balanceOf(other);

        assertEq(balanceActual, 0);
        assertEq(balancedClaimed, 0);
        assertEq(otherBalance, 0);
        assertEq(otherERC20Balance, 1000);
    }

    function test_withdrawUnderflow() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.deposit(address(this), 1000);

        vm.expectRevert(SharedLiquidityPoolErrors.InsufficientBalance.selector);
        pool.withdraw(address(this), 1001);
    }
}