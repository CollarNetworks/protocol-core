// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { CollarVaultState } from "../libs/CollarLibs.sol";

abstract contract ICollarVault {

    function openVault(
        CollarVaultState.AssetSpecifiers calldata assets,       // addresses & amounts of collateral & cash assets
        CollarVaultState.CollarOpts calldata collarOpts,        // expiry & ltv
        CollarVaultState.LiquidityOpts calldata liquidityOpts   // pool address, callstrike & amount to lock there, putstrike
    ) external virtual returns (bytes32 uuid);

    function closeVault(
        bytes32 uuid
    ) external virtual;
}