// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

abstract contract ICollarLiquidityPoolManager {

    /// @notice Whether or not a given address is a valid collar liquidity pool
    function isCollarLiquidityPool(address pool) public virtual view returns (bool);
}