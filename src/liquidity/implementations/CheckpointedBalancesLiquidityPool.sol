// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { SubdividedLiquidityPool } from "./SubdividedLiquidityPool.sol";
import { ISubdividedLiquidityPool, SubdividedLiquidityPoolErrors } from "../interfaces/ISubdividedLiquidityPool.sol";
import { ILockableSubdividedLiquidityPool, LockableSubdividedLiquidityPoolErrors } from "../interfaces/ILockableSubdividedLiquidityPool.sol";
import { LockableSubdividedLiquidityPool } from "./LockableSubdividedLiquidityPool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct LiquidityCheckpoint {
    uint256 total;          // the total amount of liquidity for this checkpoint
    bytes32 UUID;           // the UUID of the vault that created this checkpoint
    uint256 participants;   // the number of liquidity providers in this checkpoint

    mapping(address => uint256) balances;   // the balance of each liquidity provider at this checkpoint
}

abstract contract CheckpointedBalancesLiquidityPool is LockableSubdividedLiquidityPool {


    


    function lock(uint256 amount, uint24 tick) public virtual override {
        
        // since we're checkpointing balances, we need to create a checkpoint for this particular lock
        // the checkpoint is tied to the vault that is locking the liquidity
        // checkpoints are 1-to-1 with vaults, so we map them by vault UUID

        // grab the total amount liquidity available at this tick
        uint256 freeLiquidity = liquidityAtTick[tick] - lockedLiquidityAtTick[tick];

        // iterate through the liquidity providers at this tick and create a checkpoint for each
        

        super.lock(amount, tick);
    }

    function unlock(uint256 amount, uint24 tick) public virtual override {


        super.lock(amount, tick);
    }

}