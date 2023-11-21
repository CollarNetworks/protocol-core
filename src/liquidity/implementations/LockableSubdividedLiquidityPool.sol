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

    function lockLiquidityAtTick(
        uint256 amount, 
        uint24 tick
    ) public virtual override returns(uint256 totalLocked) {
        uint256 freeLiquidity = liquidityAtTickByAddress[tick][msg.sender] - lockedliquidityAtTickByAddress[tick][msg.sender];

        if (freeLiquidity < amount) revert LockableSubdividedLiquidityPoolErrors.InsufficientUnlockedBalance();

        lockedliquidityAtTick[tick] += amount;
        lockedliquidityAtTickByAddress[tick][msg.sender] += amount;

        return amount;
    }

    function unlockLiquidityAtTick(
        uint256 amount, 
        uint24 tick
    ) public virtual override returns(uint256 totalUnlocked) {
        if (lockedliquidityAtTickByAddress[tick][msg.sender] < amount) revert LockableSubdividedLiquidityPoolErrors.InsufficientLockedBalance();

        lockedliquidityAtTick[tick] -= amount;
        lockedliquidityAtTickByAddress[tick][msg.sender] -= amount;

        return amount;
    }

    function lockLiquidityAtTicks(
        uint256[] calldata amounts,
        uint24[] calldata ticks
    ) public virtual override returns(uint256 totalLocked) {
        if (amounts.length != ticks.length) revert SubdividedLiquidityPoolErrors.MismatchedArrays();

        for (uint256 i = 0; i < amounts.length; i++) {
            uint24 tick = ticks[i];
            uint256 amount = amounts[i];

            uint256 freeLiquidity = liquidityAtTick[tick] - lockedliquidityAtTick[tick];
            if (freeLiquidity < amount) revert LockableSubdividedLiquidityPoolErrors.InsufficientUnlockedBalance();

            lockedliquidityAtTick[tick] += amount;
            lockedliquidityAtTickByAddress[tick][msg.sender] += amount;
            totalLocked += amount;
        }
    }

    function unlockLiquidityAtTicks(
        uint256[] calldata amounts, 
        uint24[] calldata ticks
    ) public virtual override returns(uint256 totalUnlocked) {
        if (amounts.length != ticks.length) revert SubdividedLiquidityPoolErrors.MismatchedArrays();

        for (uint256 i = 0; i < amounts.length; i++) {
            uint24 tick = ticks[i];
            uint256 amount = amounts[i];

            if (lockedliquidityAtTickByAddress[tick][msg.sender] < amount) revert LockableSubdividedLiquidityPoolErrors.InsufficientLockedBalance();

            lockedliquidityAtTick[tick] -= amount;
            lockedliquidityAtTickByAddress[tick][msg.sender] -= amount;

            totalUnlocked += amount;
        }
    }
    
    function withdrawFromTick(
        address to, 
        uint256 amount, 
        uint24 tick
    ) public virtual override(ISubdividedLiquidityPool, SubdividedLiquidityPool) {
        // don't allow withdrawals of locked liquidity
        uint256 freeLiquidity = liquidityAtTickByAddress[tick][msg.sender] - lockedliquidityAtTickByAddress[tick][msg.sender];

        if (freeLiquidity < amount) revert LockableSubdividedLiquidityPoolErrors.InsufficientUnlockedBalance();

        super.withdrawFromTick(to, amount, tick);
    }

    function withdrawFromTicks(
        address to, 
        uint256[] calldata amounts, 
        uint24[] calldata ticks
    ) public virtual override(ISubdividedLiquidityPool, SubdividedLiquidityPool) {
        // don't allow withdrawals of locked liquidity
        uint256[] memory freeLiquidity = new uint256[](amounts.length);

        for (uint256 i = 0; i < amounts.length; i++) {
            uint24 tick = ticks[i];
            uint256 amount = amounts[i];

            freeLiquidity[i] = liquidityAtTickByAddress[tick][msg.sender] - lockedliquidityAtTickByAddress[tick][msg.sender];

            if (freeLiquidity[i] < amount) revert LockableSubdividedLiquidityPoolErrors.InsufficientUnlockedBalance();
        }

        super.withdrawFromTicks(to, amounts, ticks);
    }   
}