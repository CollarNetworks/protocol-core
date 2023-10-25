// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarEngine } from "../interfaces/IEngine.sol";

contract CollarEngine is ICollarEngine {

    constructor(address _core, address _collarLiquidityPoolManager) ICollarEngine(_core, _collarLiquidityPoolManager) {}

    function createVaultManager() external override returns (address) {
        revert("Not implemented");
    }

    function setLiquidityPoolManager(address _liquidityPoolManager) external override {
        revert("Not implemented");
    }

    function addSupportedCollateralAsset(address asset) external override {
        revert("Not implemented");
    }

    function removeSupportedCollateralAsset(address asset) external override {
        revert("Not implemented");
    }

    function addSupportedCashAsset(address asset) external override {
        revert("Not implemented");
    }

    function removeSupportedCashAsset(address asset) external override {
        revert("Not implemented");
    }
}