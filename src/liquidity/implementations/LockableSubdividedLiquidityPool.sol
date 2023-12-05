// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { SubdividedLiquidityPool } from "./SubdividedLiquidityPool.sol";
import { ISubdividedLiquidityPool, SubdividedLiquidityPoolErrors } from "../interfaces/ISubdividedLiquidityPool.sol";
import { ILockableSubdividedLiquidityPool, LockableSubdividedLiquidityPoolErrors } from "../interfaces/ILockableSubdividedLiquidityPool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LockableSubdividedLiquidityPool is ILockableSubdividedLiquidityPool, SubdividedLiquidityPool {
    /// @notice Liquidity available at each tick for each address
    mapping(uint24 => mapping(address => uint256)) public lockedliquidityAtTickByAddress;

    constructor(address _asset, uint256 _scaleFactor) SubdividedLiquidityPool(_asset, _scaleFactor) {}

    function lock(uint256 amount, uint24 tick) public virtual override {
        uint256 freeLiquidity = liquidityAtTick[tick] - lockedliquidityAtTick[tick];

        if (freeLiquidity < amount) revert LockableSubdividedLiquidityPoolErrors.InsufficientUnlockedBalance();

        lockedliquidityAtTick[tick] += amount;
        lockedliquidityAtTickByAddress[tick][msg.sender] += amount;
    }

    function unlock(uint256 amount, uint24 tick) public virtual override {
        if (lockedliquidityAtTick[tick] < amount) revert LockableSubdividedLiquidityPoolErrors.InsufficientLockedBalance();

        lockedliquidityAtTick[tick] -= amount;

        // @todo add in logic on how to unlock proportionally
    }

    function withdraw(address to, uint256 amount, uint24 tick) public virtual override(ISubdividedLiquidityPool, SubdividedLiquidityPool) {
        // don't allow withdrawals of locked liquidity
        uint256 freeLiquidity = liquidityAtTickByAddress[tick][msg.sender] - lockedliquidityAtTickByAddress[tick][msg.sender];

        if (freeLiquidity < amount) revert LockableSubdividedLiquidityPoolErrors.InsufficientUnlockedBalance();

        super.withdraw(to, amount, tick);

        // @todo fix this
    }

    function reward(uint256 /*amount*/, uint24 /*tick*/) public pure override {
        revert("Method not yet implemented");
    }
}