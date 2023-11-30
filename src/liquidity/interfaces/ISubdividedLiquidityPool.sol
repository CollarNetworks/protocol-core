// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

library SubdividedLiquidityPoolErrors {
    /// @notice Must specify ticks to deposit in
    error NoGeneralDeposits();

    /// @notice Must specify the ticks to withdraw from
    error NoGeneralWithdrawals();

    /// @notice Indicates that the arrays provided are not of equal length
    error MismatchedArrays();
}

abstract contract ISubdividedLiquidityPool {
    /// @notice Liquidity available at each tick
    mapping(uint24 => uint256) public liquidityAtTick;

    /// @notice Deposit to a specific tick
    /// @param from the address of the depositor
    /// @param amount how many assets to deposit
    /// @param tick the tick to deposit to
    function deposit(address from, uint256 amount, uint24 tick) public virtual;

    /// @notice Withdraw from a specific tick
    /// @param to the address of the withdrawer
    /// @param amount how many assets to withdraw
    /// @param tick the tick to withdraw from
    function withdraw(address to, uint256 amount, uint24 tick) public virtual;
}