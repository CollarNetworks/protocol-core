// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

interface ICollarCommonErrors {
    // auth
    error NotCollarVaultManager(address caller);
    error NotCollarPool(address caller);
    error NotCollarEngine(address caller);
}