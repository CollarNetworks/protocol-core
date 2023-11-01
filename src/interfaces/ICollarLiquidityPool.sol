// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

abstract contract ICollarLiquidityPool {
    /// @notice The address of the token supplied to this pool as liquidity
    address public asset;

    /// @notice The size of each "tick" in the pool in bps (1/100 of a percent)
    uint24 public tickSizeInBps;

    /// @notice The total amount of liquidity in the pool
    uint256 public totalSupply;

    /// @notice The total amount of liquidity at a given tick
    mapping(uint24 => uint256) public liquidityAtTick;

    /// @notice The amount of liquidity at a given tick that is locked in a vault
    /// @dev Invariant: lockedLiquidityAtTick[tick] <= liquidityAtTick[tick]
    mapping(uint24 => uint256) public lockedLiquidityAtTick;

    /// @notice This is a double-mapping that stores the amount of liquidity that a given address owns at a given tick
    /// @dev It does not specify if it is withdrawable!
    /// @dev Invariant: liquidityOwnedAtTick[address][tick] <= liquidityAtTick[tick]
    /// @dev Invariant: liquidityOwnedAtTick[address][tick] <= lockedLiquidityAtTick[tick]
    mapping(address => mapping(uint24 => uint256)) public liquidityOwnedAtTick;

    /// @notice Transfers liquidity tokens from the provider and supplied them to the pool at the given tick
    /// @param amount The amount of liquidity tokens to add
    /// @param provider The address of the liquidity provider
    /// @param tick The tick to add liquidity at
    function addSingleTickLiquidity(uint256 amount, uint24 tick, address provider) external virtual;

    /// @notice Transfers liquidity tokens from the provider and supplies them to the pool at the given ticks
    /// @dev The provider must have approved transfer of tokens to the caller, if not the caller themselves; the caller
    /// must have approved transfer of tokens to the pool
    /// @param amounts The amounts of liquidity tokens to add - ordered
    /// @param ticks The ticks to add liquidity at - ordered
    /// @param provider The address of the liquidity provider
    function addMultiTickLiquidity(uint256[] calldata amounts, uint24[] calldata ticks, address provider) external virtual;

    /// @notice Transfers liquidity tokens from the pool and returns them to the provider
    /// @dev Will revert if the sender does not own the specified liquidity!
    /// @param amount The amount of liquidity tokens to remove
    /// @param tick The tick to remove liquidity from
    /// @param provider The address of the liquidity provider
    /// @param recipient The address of the recipient for the liquidity once withdrawn
    function removeSingleTickLiquidity(uint256 amount, uint24 tick, address provider, address recipient) external virtual;

    /// @notice Transfers liquidity tokens from the pool and returns them to the provider
    /// @dev Will revert if the sender does not own the specified liquidity!
    /// @param amounts The amounts of liquidity tokens to remove - ordered
    /// @param ticks The ticks to remove liquidity from - ordered
    /// @param provider The address of the liquidity provider
    /// @param recipient The address of the recipient for the liquidity once withdrawn
    function removeMultiTickLiquidity(uint256[] calldata amounts, uint24[] calldata ticks, address provider, address recipient) external virtual;

    /// @notice Locks liquidity at a given tick
    /// @param amount The amount of liquidity to lock
    /// @param tick The tick to lock liquidity at
    function lockLiquidityAtTick(uint256 amount, uint24 tick) external virtual;

    /// @notice Locks liquidity at multiple ticks
    /// @param amounts The amounts of liquidity to lock - ordered
    /// @param ticks The ticks to lock liquidity at - ordered
    function lockLiquidity(uint256[] calldata amounts, uint24[] calldata ticks) external virtual;

    /// @notice Unlocks liquidity at a given tick
    /// @param amount The amount of liquidity to unlock
    /// @param tick The tick to unlock liquidity at
    function unlockLiquidityAtTick(uint256 amount, uint24 tick) external virtual;

    /// @notice Unlocks liquidity at multiple ticks
    /// @param amounts The amounts of liquidity to unlock - ordered
    /// @param ticks The ticks to unlock liquidity at - ordered
    function unlockLiquidity(uint256[] calldata amounts, uint24[] calldata ticks) external virtual;
}