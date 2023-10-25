// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarLiquidityPool } from "../interfaces/ICollarLiquidityPool.sol";

contract CollarLiquidityPool is ICollarLiquidityPool {

    constructor(
        address _asset,
        uint24 _tickSizeInBps
    ) {
        asset = _asset;
        tickSizeInBps = _tickSizeInBps;
    }

    function addSingleTickLiquidity(uint256 amount, uint24 tick, address provider) external override {
        revert("Not implemented");
    }

    function addMultiTickLiquidity(uint256[] calldata amounts, uint24[] calldata ticks, address provider) external override {
        revert("Not implemented");
    }

    function removeSingleTickLiquidity(uint256 amount, uint24 tick, address provider, address recipient) external override {
        revert("Not implemented");
    }

    function removeMultiTickLiquidity(uint256[] calldata amounts, uint24[] calldata ticks, address provider, address recipient) external override {
        revert("Not implemented");
    }
}