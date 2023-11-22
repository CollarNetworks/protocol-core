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
}

abstract contract ILockableSubdividedLiquidityPool is ISubdividedLiquidityPool {
    /// @notice Locked liquidity at each tick
    mapping(uint24 => uint256) public lockedliquidityAtTick;

    /// @notice Lock liquidity at a specific tick
    /// @param amount how much to lock
    /// @param tick the tick to lock at
    function lockLiquidityAtTick(uint256 amount, uint24 tick) public virtual returns(uint256 totalLocked);

    /// @notice Unlock liquidity at a specific tick
    /// @param amount how much to unlock
    /// @param tick the tick to unlock at
    function unlockLiquidityAtTick(uint256 amount, uint24 tick) public virtual returns(uint256 totalUnlocked);

    /// @notice Plural form of lockLiquidityAtTick
    /// @param amounts how much to lock at each tick
    /// @param ticks the ticks to lock at
    function lockLiquidityAtTicks(uint256[] calldata amounts, uint24[] calldata ticks) public virtual returns (uint256 totalLocked);

    /// @notice Given a total amount of liquidity to lock and a set of ratios that sum to 1e12 and the ticks to lock them, at - do it
    /// @param total how much to lock
    /// @param ratios the ratios to lock at - must sum to 1e12
    /// @param ticks the ticks to lock at
    function lockLiquidityAtTicks(uint256 total, uint256[] calldata ratios, uint24[] calldata ticks) public virtual returns (uint256 totalLocked);

    /// @notice Plural form of unlockLiquidityAtTick
    /// @param amounts how much to unlock at each tick
    /// @param ticks the ticks to unlock at
    function unlockLiquidityAtTicks(uint256[] calldata amounts, uint24[] calldata ticks) public virtual returns (uint256 totalUnlocked);

    /// @notice Given a total amount of liquidity to unlock and a set of ratios that sum to 1e12 and the ticks to unlock them, at - do it
    /// @param total how much to unlock
    /// @param ratios the ratios to unlock at - must sum to 1e12
    /// @param ticks the ticks to unlock at
    function unlockLiquidityAtTicks(uint256 total, uint256[] calldata ratios, uint24[] calldata ticks) public virtual returns (uint256 totalUnlocked);

    /// @notice Reward liquidity to a specific tick
    /// @param amount how much to reward
    /// @param tick the tick to reward at
    function rewardLiquidityToTick(uint256 amount, uint24 tick) public virtual;

    /// @notice Reward liquidity to ticks
    /// @param amounts how much to reward at each tick
    /// @param ticks the ticks to reward at
    function rewardLiquidityToTicks(uint256[] calldata amounts, uint24[] calldata ticks) public virtual;

    /// @notice Given a total amount of liquidity to reward and a set of ratios that sum to 1e12 and the ticks to reward them, at - do it
    /// @param total how much to reward
    /// @param ratios the ratios to reward at - must sum to 1e12
    /// @param ticks the ticks to reward at
    function rewardLiquidityToTicks(uint256 total, uint256[] calldata ratios, uint24[] calldata ticks) public virtual;
}