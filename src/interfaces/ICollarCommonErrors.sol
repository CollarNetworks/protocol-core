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
    error NotCollarVaultOwner(address caller);

    // parameter errors shared across contracts
    error InvalidDuration();
    error InvalidCashAsset();
    error InvalidCollateralAsset();
    error InvalidCashAmount();
    error InvalidCollateralAmount();
    error InvalidVaultManager();
    error InvalidVault();
    error InvalidLiquidityPool();
    error InvalidAssetPrice();
    error InactiveVault();

    // state-related errors shared across contracts
    error VaultNotFinalized();
    error VaultNotActive();

    // generic arg errors
    error AddressCannotBeZero();
    error AmountCannotBeZero();
    error InvalidAmount();
}