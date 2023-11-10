// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "./ILiquidityPool.sol";

abstract contract ISubdividedLiquidityPool {
    /// @notice Must specify ticks to deposit in
    error NoGeneralDeposits();

    /// @notice Must specify the ticks to withdraw from
    error NoGeneralWithdrawals();

    /// @notice Liquidity available at each tick
    mapping(uint24 => uint256) public liquidityAtTick;

    /// @notice Deposit to a specific tick
    /// @param from the address of the depositor
    /// @param amount how many assets to deposit
    /// @param tick the tick to deposit to
    function depositToTick(address from, uint256 amount, uint24 tick) public virtual;

    /// @notice Plural form of depositToTick
    /// @param from the address of the depositor
    /// @param amounts the amounts to deposit into each tick
    /// @param ticks the ticks to deposit to
    function depositToTicks(address from, uint256[] calldata amounts, uint24[] calldata ticks) public virtual;

    /// @notice Withdraw from a specific tick
    /// @param to the address of the withdrawer
    /// @param amount how many assets to withdraw
    /// @param tick the tick to withdraw from
    function withdrawFromTick(address to, uint256 amount, uint24 tick) public virtual;

    /// @notice Plural form of withdrawFromTick
    /// @param to the address of the withdrawer
    /// @param amounts the amounts to withdraw from each tick
    /// @param ticks the ticks to withdraw from
    function withrawFromTicks(address to, uint256[] calldata amounts, uint24[] calldata ticks) public virtual;
}