// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import { LiquidityPool } from "../../src/liquidity/implementations/LiquidityPool.sol";
import { LiquidityPoolErrors } from "../../src/liquidity/interfaces/ILiquidityPool.sol";
import { TestERC20 } from "../utils/TestERC20.sol";

contract LiquidityPoolTest is Test {
    LiquidityPool pool;
    TestERC20 asset;
    address other;

    function setUp() public {
        asset = new TestERC20("Test", "TST");
        pool = new LiquidityPool(address(asset));
        other = makeAddr("other");
    }

    function test_balance() public {
        balanceCheck();
        asset.mint(address(pool), 1000);
        balanceCheck();
    }

    function test_depositFromSelf() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1000);
        pool.deposit(address(this), 1000);

        uint256 balanceActual = asset.balanceOf(address(pool));
        uint256 balancedClaimed = pool.balance();

        assertEq(balanceActual, 1000);
        assertEq(balancedClaimed, 1000);
    }

    function test_depositFromOther() public {
        asset.mint(other, 1000);
 
        startHoax(other);
            asset.approve(address(this), 1000);
            asset.approve(address(pool), 1000);
        vm.stopPrank();

        pool.deposit(other, 1000);
        
        uint256 balanceActual = asset.balanceOf(address(pool));
        uint256 balancedClaimed = pool.balance();

        assertEq(balanceActual, 1000);
        assertEq(balancedClaimed, 1000);
    }

    function test_depositWithoutApprovalFromSelf() public {
        asset.mint(address(this), 1000);

        vm.expectRevert("ERC20: insufficient allowance");
        pool.deposit(address(this), 1000);
    }

    function test_depositWithoutApprovalFromOther() public {
        asset.mint(other, 1000);

        vm.expectRevert(LiquidityPoolErrors.InsufficientAllowance.selector);
        pool.deposit(other, 1000);

        hoax(other);
        asset.approve(address(this), 1000);

        vm.expectRevert(LiquidityPoolErrors.InsufficientAllowance.selector);
        pool.deposit(other, 1000);
    }

    function test_depositWithoutEnoughBalance() public {
        asset.mint(address(this), 1000);
        asset.approve(address(pool), 1001);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        pool.deposit(address(this), 1001);
    }

    function test_withdraw() public {
        asset.mint(address(pool), 1000);
        pool.withdraw(address(this), 1000);
        uint256 balance = asset.balanceOf(address(this));
        assertEq(balance, 1000);
    }

    function test_withdrawToOther() public {
        asset.mint(address(pool), 1000);
        pool.withdraw(other, 1000);
        uint256 balance = asset.balanceOf(other);
        assertEq(balance, 1000);
    }

    function test_withdrawUnderflow() public {
        asset.mint(address(pool), 1000);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        pool.withdraw(address(this), 1001);
    }

    function balanceCheck() internal {
        // should always returns the current erc20 balance of the asset token
 
        uint256 balanceActual = TestERC20(asset).balanceOf(address(pool));
        uint256 balanceClaimed = pool.balance();

        assertEq(balanceActual, balanceClaimed);
    }
}