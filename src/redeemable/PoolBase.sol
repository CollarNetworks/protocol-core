// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

abstract contract PoolBase {
    uint256 public constant UNALLOCATED_SLOT = type(uint256).max;

    mapping(uint256 slot => uint256 liquidity) public slotLiquidity;
    mapping(address provider => mapping(uint256 slot => uint256 amount)) public providerLiquidityBySlot;

    function addLiquidity(
        uint256 slot,
        uint256 amount
    ) external virtual;

    function removeLiquidity(
        uint256 slot,
        uint256 amount
    ) external virtual;

    function reallocateLiquidity(
        uint256 sourceSlot,
        uint256 destinationSlot,
        uint256 amount
    ) external virtual;

}