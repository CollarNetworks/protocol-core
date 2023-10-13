// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

interface ICollarLiquidityPoolLens {
    /// @notice Returns the available liquidity in the pool
    function availableSupply() external view returns (uint256);

    /// @notice Returns the highest tick with liquidity
    function getMaxLiquidityTick() external view returns (uint24);

    /// @notice Returns the lowest tick with liquidity
    function getMinLiquidityTick() external view returns (uint24);

    /// @notice Returns the total amount of liquidity in the pool at a given tick
    /// @param tick The tick to check liquidity at
    function liquidityAtTick(uint24 tick) external view returns (uint256);

    /// @notice Returns the amount of liquidity in the pool at a given tick available to be used (ie, not locked in a vault)
    function availableLiquidityAtTick(uint24 tick) external view returns (uint256);

    /// @notice Returns the amount of liquidity in the pool at a given tick locked in a vault
    function lockedLiquidityAtTick(uint24 tick) external view returns (uint256);

    /// @notice Returns all data about a given tick
    function getTick(uint24 index) external view returns (uint256 total, uint256 available);

    /// @notice Given a tick index, returns the bips value that this represents (lower bound)
    function tickToBips(uint24 tick) external view returns (uint24);

    /// @notice Given a bips value, returns the tick index that this represents (lower bound)
    function bipsToTick(uint24 bips) external view returns (uint24);

    /// @notice Returns the amount of liquidity in the pool between two ticks
    function getLiquidityInTickRange(uint24 tickLower, uint24 tickUpper) external view returns (uint256);

    /// @notice Returns the amount of liquidity in the pool between two bips values
    function getLiquidityInBipsRange(uint24 bipsLower, uint24 bipsUpper) external view returns (uint256);

    /// @notice Returns the amount of liquidity in the pool, starting with the highest bip and counting down,
    /// that composes together to form a weighted average (mean) of the supplied value
    /// @param bipsMean The mean value to calculate liquidity to
    function getLiquidityToMeanValue(uint24 bipsMean) external view returns (uint256);
}