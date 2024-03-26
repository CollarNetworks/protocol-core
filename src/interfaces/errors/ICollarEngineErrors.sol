// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarCommonErrors } from "./ICollarCommonErrors.sol";

interface ICollarEngineErrors is ICollarCommonErrors {
    // pools & vault managers
    error VaultManagerAlreadyExists(address user, address vaultManager);
    error LiquidityPoolAlreadyAdded(address pool);

    // assets
    error CollateralAssetNotSupported(address asset);
    error CashAssetNotSupported(address asset);
    error CollateralAssetAlreadySupported(address asset);
    error CashAssetAlreadySupported(address asset);

    // ltv & duration
    error LTVNotSupported(uint256 ltv);
    error LTVAlreadySupported(uint256 ltv);
    error CollarDurationNotSupported();
}
