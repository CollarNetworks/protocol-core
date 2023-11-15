// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarEngine } from "../interfaces/IEngine.sol";
import { CollarVaultManager } from "./VaultManager.sol";

contract CollarEngine is ICollarEngine {
    constructor(address _core, address _collarLiquidityPoolManager) ICollarEngine(_core, _collarLiquidityPoolManager) {}

    function createVaultManager() external override returns (address _vaultManager) {
        if (addressToVaultManager[msg.sender] != address(0)) {
            revert VaultManagerAlreadyExists(msg.sender, addressToVaultManager[msg.sender]);
        }

        address vaultManager = address(new CollarVaultManager(msg.sender));
        addressToVaultManager[msg.sender] = vaultManager;

        return vaultManager;
    }

    function setLiquidityPoolManager(
        address _liquidityPoolManager
    ) external override {
        if (_liquidityPoolManager == address(0)) revert InvalidZeroAddress(_liquidityPoolManager);
    
        liquidityPoolManager = _liquidityPoolManager;
    }

    function addSupportedCollateralAsset(
        address asset
    ) external override isNotValidCollateralAsset(asset) {
        isSupportedCollateralAsset[asset] = true;
    }

    function removeSupportedCollateralAsset(
        address asset
    ) external override isValidCollateralAsset(asset) {
        isSupportedCollateralAsset[asset] = false;
    }

    function addSupportedCashAsset(
        address asset
    ) external override isNotValidCashAsset(asset) {
        isSupportedCashAsset[asset] = true;
    }

    function removeSupportedCashAsset(
        address asset
    ) external override isValidCashAsset(asset) {
        isSupportedCashAsset[asset] = false;
    }

    function addSupportedCollarLength(
        uint256 length
    ) external override isSupportedCollarLength(length) {
        isValidCollarLength[length] = true;
    }

    function removeSupportedCollarLength(
        uint256 length
    ) external override isSupportedCollarLength(length) {
        isValidCollarLength[length] = false;
    }
}