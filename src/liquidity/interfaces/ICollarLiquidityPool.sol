// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

/// @notice The interface for a collar liquidity pool
abstract contract ICollarLiquidityPool {
    /// @notice Given a particular tick index, returns the bps offset from the current price
    function tickToBpsOffset(uint24 tick) public pure virtual returns (uint256);

    /// @notice Given a particular tick index and a starting price, returns the price at that tick
    function tickToPrice(uint24 tick, uint256 startingPrice) public pure virtual returns (uint256);
}