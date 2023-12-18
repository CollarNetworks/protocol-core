// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

abstract contract ICollarPool {
    uint256 public constant UNALLOCATED_SLOT = type(uint256).max;
    
    uint256 immutable public tickScaleFactor;
    address immutable public engine;
    address immutable public cashAsset;

    mapping(uint256 slot => uint256 liquidity) public slotLiquidity;
    mapping(address provider => mapping(uint256 slot => uint256 amount)) public providerLiquidityBySlot;

    constructor(address _engine, uint256 _tickScaleFactor, address _cashAsset) {
        tickScaleFactor = _tickScaleFactor;
        engine = _engine;
        cashAsset = _cashAsset;
    }

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