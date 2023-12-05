// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ISubdividedLiquidityPool } from "./ISubdividedLiquidityPool.sol";

library LockableSubdividedLiquidityPoolErrors {
    /// @notice Indicates that there is not enough *unlocked* balance to perform the action
    error InsufficientUnlockedBalance();

    /// @notice Indicates that there is not enough *locked* balance to perform this act4ion
    error InsufficientLockedBalance();

    /// @notice Indicates that there is some error in the parameters provided
    error InvalidParams();
}

abstract contract ILockableSubdividedLiquidityPool is ISubdividedLiquidityPool {
    /// @notice Locked liquidity at each tick
    mapping(uint24 => uint256) public lockedLiquidityAtTick;

    /// @notice Lock liquidity at a specific tick
    /// @param amount how much to lock
    /// @param tick the tick to lock at
    function lock(uint256 amount, uint24 tick) public virtual;

    /// @notice Unlock liquidity at a specific tick
    /// @param amount how much to unlock
    /// @param tick the tick to unlock at
    function unlock(uint256 amount, uint24 tick) public virtual;

    /// @notice Reward liquidity to a specific tick
    /// @param amount how much to reward
    /// @param tick the tick to reward at
    function reward(uint256 amount, uint24 tick) public virtual;

    /// @notice Penalize liquidity at a specific tick
    /// @param amount how much to penalize
    /// @param tick the tick to penalize at
    function penalize(address toWhere, uint256 amount, uint24 tick) public virtual;
}