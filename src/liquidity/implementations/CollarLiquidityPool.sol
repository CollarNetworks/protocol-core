// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { LockableSubdividedLiquidityPool } from "./LockableSubdividedLiquidityPool.sol";
import { ICollarLiquidityPool } from "../interfaces/ICollarLiquidityPool.sol";

contract CollarLiquidityPool is ICollarLiquidityPool, LockableSubdividedLiquidityPool {
    constructor(address _asset) LockableSubdividedLiquidityPool(_asset) {}

    function tickToBpsOffset(uint24 tick) public pure override returns (uint256) {
        return tick * 100;
    }

    function tickToPrice(uint24 tick, uint256 startingPrice) public pure override returns (uint256) {
        return startingPrice * (100 + tickToBpsOffset(tick)) / 100;
    }
 }