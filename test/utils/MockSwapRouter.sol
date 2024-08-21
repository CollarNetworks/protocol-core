// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";

contract MockSwapRouter {
    address public factory = address(1); // not zero
    uint toReturn;
    uint toTransfer;

    function exactInputSingle(IV3SwapRouter.ExactInputSingleParams memory params)
        external
        returns (uint amountOut)
    {
        ERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        amountOut = toReturn;
        ERC20(params.tokenOut).transfer(msg.sender, toTransfer);
    }

    function setupSwap(uint _toReturn, uint _toTransfer) external {
        toReturn = _toReturn;
        toTransfer = _toTransfer;
    }
}
