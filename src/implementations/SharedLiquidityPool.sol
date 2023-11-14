// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "../interfaces/ISharedLiquidityPool.sol";
import "./LiquidityPool.sol";

contract SharedLiquidityPool is ISharedLiquidityPool, LiquidityPool {
    constructor(address _asset) LiquidityPool(_asset) {}

    function deposit(address from, uint256 amount) public virtual override {
        balanceOf[msg.sender] += amount;
        super.deposit(from, amount);
    }

    function withdraw(address to, uint256 amount) public virtual override {
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();

        balanceOf[msg.sender] -= amount;
        super.withdraw(to, amount);
    }
}