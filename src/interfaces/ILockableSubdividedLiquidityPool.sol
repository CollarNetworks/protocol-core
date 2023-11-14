// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ISubdividedLiquidityPool } from "./ISubdividedLiquidityPool.sol";

/// @notice Indicates that there is not enough *unlocked* balance to perform the action
error InsufficientUnlockedBalance();

/// @notice Indicates that there is not enough *locked* balance to perform this act4ion
error InsufficientLockedBalance();

abstract contract ILockableSubdividedLiquidityPool is ISubdividedLiquidityPool {
    /// @notice Locked liquidity at each tick
    mapping(uint24 => uint256) public lockedliquidityAtTick;

    /// @notice Lock liquidity at a specific tick
    /// @param amount how much to lock
    /// @param tick the tick to lock at
    function lockLiquidityAtTick(uint256 amount, uint24 tick) public virtual;

    /// @notice Unlock liquidity at a specific tick
    /// @param amount how much to unlock
    /// @param tick the tick to unlock at
    function unlockLiquidityAtTick(uint256 amount, uint24 tick) public virtual;

    /// @notice Plural form of lockLiquidityAtTick
    /// @param amounts how much to lock at each tick
    /// @param ticks the ticks to lock at
    function lockLiquidityAtTicks(uint256[] calldata amounts, uint24[] calldata ticks) public virtual;

    /// @notice Plural form of unlockLiquidityAtTick
    /// @param amounts how much to unlock at each tick
    /// @param ticks the ticks to unlock at
    function unlockLiquidityAtTicks(uint256[] calldata amounts, uint24[] calldata ticks) public virtual;
}
