// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

interface ICollarEngineEvents {
    // regular user actions
    event VaultManagerCreated(address indexed vaultManager, address indexed owner);

    // auth'd actions
    event LiquidityPoolAdded(address indexed liquidityPool);
    event LiquidityPoolRemoved(address indexed liquidityPool);
    event CollateralAssetAdded(address indexed collateralAsset);
    event CollateralAssetRemoved(address indexed collateralAsset);
    event CashAssetAdded(address indexed cashAsset);
    event CashAssetRemoved(address indexed cashAsset);
    event CollarDurationAdded(uint256 indexed duration);
    event CollarDurationRemoved(uint256 indexed duration);
    event LTVAdded(uint256 indexed ltv);
    event LTVRemoved(uint256 indexed ltv);
}
