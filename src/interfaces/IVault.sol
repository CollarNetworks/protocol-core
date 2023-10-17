// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

abstract contract ICollarVault {
    address public collateral;
    address public cashAsset;

    uint256 public initialCollateral;
    uint256 public initialCash;

    uint256 public putStrikePrice;
    uint256 public callStrikePrice;

    uint256 public expiry;

    function depositCash(uint256 amount, address from) external virtual returns (uint256);
    function withrawCash(uint256 amount, address to) external virtual returns (uint256);
}