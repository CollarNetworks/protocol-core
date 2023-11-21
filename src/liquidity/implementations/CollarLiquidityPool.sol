// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { LockableSubdividedLiquidityPool } from "./LockableSubdividedLiquidityPool.sol";
import { ICollarLiquidityPool } from "../interfaces/ICollarLiquidityPool.sol";

contract CollarLiquidityPool is ICollarLiquidityPool, LockableSubdividedLiquidityPool {
    constructor(address _asset, uint256 _scaleFactor) LockableSubdividedLiquidityPool(_asset, _scaleFactor) {}
 }