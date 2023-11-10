// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "../interfaces/ILiquidityPool.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LiquidityPool is ILiquidityPool {
    function balance() public view virtual override returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }

    function deposit(address from, uint256 amount) public virtual override{
        IERC20(asset).transferFrom(from, address(this), amount);
    }

    function withdraw(address to, uint256 amount) public virtual override {
        IERC20(asset).transfer(to, amount);
    }
}