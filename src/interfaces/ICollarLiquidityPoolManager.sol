// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

abstract contract ICollarLiquidityPoolManager {
    /// @notice Whether or not the specified address is a valid system liquidity pool
    /// @dev The method of how the liquidity actually works is not relevant here
    mapping(address => bool) public isCollarLiquidityPool;

    /// @notice Removes the specified address as a valid system liquidity pool
    /// @param source The address to remove
    function removeLiquidityPool(address source) external virtual;

    /// @notice Returns the liquidity source for the specified asset, timeframe, and granularity (tick size)
    /// @param asset The address of the asset
    /// @param timeframe The timeframe that liquidity can be locked for in this source
    /// @param bpsGranularity The granularity of the liquidity source in bps (1/100 of a percent)
    function getLiquidityPool(
        address asset,
        uint256 timeframe,
        uint24 bpsGranularity
    ) external view virtual returns (address);

    /// @notice Creates a liquidity pool (if not yet existing) for the specified asset, timeframe, and granularity (tick size)
    /// @param asset The address of the asset
    /// @param timeframe The timeframe that liquidity can be locked for in this source
    /// @param bpsGranularity The granularity of the liquidity source in bps (1/100 of a percent)
    function createLiquidityPool(
        address asset,
        uint256 timeframe,
        uint24 bpsGranularity
    ) external view virtual returns (address);
}