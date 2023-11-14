// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "./SharedLiquidityPool.sol";
import "../interfaces/ISubdividedLiquidityPool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SubdividedLiquidityPool is ISubdividedLiquidityPool, SharedLiquidityPool {
    /// @notice Liquidity available at each tick for each address
    mapping(uint24 => mapping(address => uint256)) public liquidityAtTickByAddress;

    constructor(address _asset) SharedLiquidityPool(_asset) {}

    function depositToTick(address from, uint256 amount, uint24 tick) public virtual override {
        liquidityAtTick[tick] += amount;
        liquidityAtTickByAddress[tick][msg.sender] += amount;
        super.deposit(from, amount);
    }

    function withdrawFromTick(address to, uint256 amount, uint24 tick) public virtual override {
        liquidityAtTick[tick] -= amount;
        liquidityAtTickByAddress[tick][msg.sender] -= amount;
        super.withdraw(to, amount);
    }

    function depositToTicks(address from, uint256[] calldata amounts, uint24[] calldata ticks) public virtual override {
        if (amounts.length != ticks.length) revert MismatchedArrays();
        
        uint256 totalToDeposit = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            uint24 tick = ticks[i];
            uint256 amount = amounts[i];

            liquidityAtTick[tick] += amount;
            liquidityAtTickByAddress[tick][msg.sender] += amount;
            totalToDeposit += amount;
        }

        super.deposit(from, totalToDeposit);
    }

    function withdrawFromTicks(address to, uint256[] calldata amounts, uint24[] calldata ticks) public virtual override {
        if (amounts.length != ticks.length) revert MismatchedArrays();
        
        uint256 totalToWithdraw = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            uint24 tick = ticks[i];
            uint256 amount = amounts[i];

            if (liquidityAtTickByAddress[tick][msg.sender] < amount) revert InsufficientBalance();    

            liquidityAtTick[tick] -= amount;
            liquidityAtTickByAddress[tick][msg.sender] -= amount;
            totalToWithdraw += amount;
        }

        super.withdraw(to, totalToWithdraw);
    }

    /// @dev We disallow explicitly calling the general form of deposit from here on out
    function deposit(address /*from*/, uint256 /*amount*/) public virtual override {
        revert NoGeneralDeposits();
    }

    /// @dev We disallow explicitly calling the general form of withdraw from here on out
    function withdraw(address /*to*/, uint256 /*amount*/) public virtual override {
        revert NoGeneralWithdrawals();
    }
}