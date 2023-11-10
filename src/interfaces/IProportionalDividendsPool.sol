// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

abstract contract IProportionalDividendsPool {
    /// @notice The amount of dividends per liquidity token per tick
    mapping(uint24 => uint256) public dividendsPerTick;

    /// @notice Pay dividends to the pool for a particular tick
    /// @param tick The tick for which to pay dividends
    /// @param amount The amount of dividends to pay
    function payDividends(uint24 tick, uint256 amount) public virtual;
}