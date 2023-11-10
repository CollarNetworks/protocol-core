// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

abstract contract ILiquidityPool {
    /// @notice Each liquidity pool can hold only one asset type
    address public asset;

    /// @notice Returns the total amount of the liquidity token owned by the pool
    function balance() external view virtual returns (uint256);

    /// @notice Deposits assets into the pool
    /// @param amount how many assets to deposit
    function deposit(address from, uint256 amount) external virtual;

    /// @notice Withdraws assets from the pool
    /// @param amount how many assets to withdraw
    function withdraw(address to, uint256 amount) external virtual;
}