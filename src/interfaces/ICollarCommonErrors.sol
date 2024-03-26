// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

interface ICollarCommonErrors {
    // execution flow error
    error InvalidState();
    
    // auth
    error NotCollarVaultManager(address caller);
    error NotCollarPool(address caller);
    error NotCollarEngine(address caller);

    // parameter errors shared across contracts
    error InvalidDuration();

    // generic arg errors
    error AmountCannotBeZero();
    error InvalidCashAsset();
    error InvalidCollateralAsset();
    error InvalidCashAmount();
    error InvalidCollateralAmount();
}