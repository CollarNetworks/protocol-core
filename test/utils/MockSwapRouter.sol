// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IV3SwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";

contract MockSwapRouter {
    uint amountToReturn;
    uint amountToTransfer;

    function exactInputSingle(IV3SwapRouter.ExactInputSingleParams memory params)
        external
        returns (uint amountOut)
    {
        amountOut = params.amountOutMinimum;

        ERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        amountOut = amountToReturn;
        if (amountOut == 0) {
            amountOut = params.amountOutMinimum;
        }
        uint transferAmount = amountToTransfer;
        if (transferAmount == 0) {
            transferAmount = amountOut;
        }
        ERC20(params.tokenOut).transfer(msg.sender, transferAmount);
    }

    function setAmountToReturn(uint amount) external {
        amountToReturn = amount;
    }

    function setTransferAmount(uint amount) external {
        amountToTransfer = amount;
    }
}
