// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { SharedLiquidityPool } from "./SharedLiquidityPool.sol";
import { ISubdividedLiquidityPool, SubdividedLiquidityPoolErrors } from "../interfaces/ISubdividedLiquidityPool.sol";
import { SharedLiquidityPoolErrors } from "../interfaces/ISharedLiquidityPool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SubdividedLiquidityPool is ISubdividedLiquidityPool, SharedLiquidityPool {
    uint256 public immutable scaleFactor;

    /// @notice Liquidity available at each tick for each address
    mapping(uint24 => mapping(address => uint256)) public liquidityAtTickByAddress;

    constructor(address _asset, uint256 _scaleFactor) SharedLiquidityPool(_asset) {
        scaleFactor = _scaleFactor;
    }

    function deposit(address from, uint256 amount, uint24 tick) public virtual override {
        liquidityAtTick[tick] += amount;
        liquidityAtTickByAddress[tick][msg.sender] += amount;
        super.deposit(from, amount);
    }

    function withdraw(address to, uint256 amount, uint24 tick) public virtual override {
        liquidityAtTick[tick] -= amount;
        liquidityAtTickByAddress[tick][msg.sender] -= amount;
        super.withdraw(to, amount);
    }

    /// @dev We disallow explicitly calling the general form of deposit from here on out
    function deposit(address /*from*/, uint256 /*amount*/) public virtual override {
        revert SubdividedLiquidityPoolErrors.NoGeneralDeposits();
    }

    /// @dev We disallow explicitly calling the general form of withdraw from here on out
    function withdraw(address /*to*/, uint256 /*amount*/) public virtual override {
        revert SubdividedLiquidityPoolErrors.NoGeneralWithdrawals();
    }
}