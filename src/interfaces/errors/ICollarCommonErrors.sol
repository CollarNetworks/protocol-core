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
    error NotCollarVaultManager();
    error NotCollarPool();
    error NotCollarEngine();
    error NotCollarVaultOwner();

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
    error VaultNotFinalizable();
    error VaultNotActive();

    // generic arg errors
    error AddressCannotBeZero();
    error AmountCannotBeZero();
    error InvalidAmount();
}
