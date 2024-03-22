// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

/// @notice Various constants used throughout the system
abstract contract Constants {

    // one hundred percent, in basis points
    uint256 public constant ONE_HUNDRED_PERCENT = 10_000;

    // precision multiplier to be used when expanding small numbers before division, etc
    uint256 public constant PRECISION_MULTIPLIER = 1e18;
}
