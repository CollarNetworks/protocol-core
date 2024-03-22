// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

abstract contract ICollarEngineErrors {
    error VaultManagerAlreadyExists(address user, address vaultManager);
    error LiquidityPoolAlreadyAdded(address pool);
    error CollateralAssetNotSupported(address asset);
    error CashAssetNotSupported(address asset);
    error CollateralAssetAlreadySupported(address asset);
    error CashAssetAlreadySupported(address asset);
    error InvalidZeroAddress(address addr);
    error InvalidCashAmount(uint256 amount);
    error InvalidCollateralAmount(uint256 amount);
    error InvalidLiquidityPool(address pool);
    error CollarLengthNotSupported(uint256 length);
    error InvalidLiquidityOpts();
    error AssetNotSupported(address asset);
    error AssetAlreadySupported(address asset);
    error InvalidVaultManager(address vaultManager);
    error LTVNotSupported(uint256 ltv);
    error LTVAlreadySupported(uint256 ltv);
}
