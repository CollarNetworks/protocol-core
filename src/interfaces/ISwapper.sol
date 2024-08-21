// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISwapper {
    function swap(IERC20 assetIn, IERC20 assetOut, uint amountIn, uint minAmountOut, bytes calldata extraData)
        external
        returns (uint amountOut);
    function VERSION() external returns (string memory);
}
