// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ISwapRouter } from "@uni-v3-periphery/interfaces/ISwapRouter.sol";

contract MockBadUniRouter {
    address public factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    function exactInputSingle(ISwapRouter.ExactInputSingleParams memory params) external returns (uint256 amountOut) {
        amountOut = params.amountOutMinimum - 1;

        ERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        ERC20(params.tokenOut).transfer(msg.sender, amountOut - 1);
    }
}
