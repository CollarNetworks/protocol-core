// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

library SharedLiquidityPoolErrors {
    /// @notice Indicates the user tried to withdraw more than they have in balance
    error InsufficientBalance();
}

/// @notice Allows extends liquidity pools to have balances tracked per address
abstract contract ISharedLiquidityPool {
    /// @notice Balance of each depositor
    mapping(address => uint256) public balanceOf;
}