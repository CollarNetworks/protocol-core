// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarEngine } from "../interfaces/ICollarEngine.sol";
import { CollarVaultManager } from "./CollarVaultManager.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract CollarEngine is ICollarEngine, Ownable {
    constructor(address _dexRouter) ICollarEngine(_dexRouter) Ownable(msg.sender) { }

    function createVaultManager() external override returns (address _vaultManager) {
        if (addressToVaultManager[msg.sender] != address(0)) {
            revert VaultManagerAlreadyExists(msg.sender, addressToVaultManager[msg.sender]);
        }

        address vaultManager = address(new CollarVaultManager(address(this), msg.sender));
        addressToVaultManager[msg.sender] = vaultManager;
        vaultManagers[vaultManager] = true;

        return vaultManager;
    }

    function addLiquidityPool(address pool) external override onlyOwner isNotValidLiquidityPool(pool) {
        isLiquidityPool[pool] = true;
    }

    function removeLiquidityPool(address pool) external override onlyOwner isValidLiquidityPool(pool) {
        isLiquidityPool[pool] = false;
    }

    function addSupportedCollateralAsset(address asset) external override onlyOwner isNotValidCollateralAsset(asset) {
        isSupportedCollateralAsset[asset] = true;
    }

    function removeSupportedCollateralAsset(address asset) external override onlyOwner isValidCollateralAsset(asset) {
        isSupportedCollateralAsset[asset] = false;
    }

    function addSupportedCashAsset(address asset) external override onlyOwner isNotValidCashAsset(asset) {
        isSupportedCashAsset[asset] = true;
    }

    function removeSupportedCashAsset(address asset) external override onlyOwner isValidCashAsset(asset) {
        isSupportedCashAsset[asset] = false;
    }

    function addSupportedCollarLength(uint256 length) external override onlyOwner isNotSupportedCollarLength(length) {
        isValidCollarLength[length] = true;
    }

    function removeSupportedCollarLength(uint256 length) external override onlyOwner isSupportedCollarLength(length) {
        isValidCollarLength[length] = false;
    }

    function getHistoricalAssetPrice(address, /*asset*/ uint256 /*timestamp*/ ) external view virtual override returns (uint256) {
        revert("Method not yet implemented");
    }

    function getCurrentAssetPrice(address asset) external view virtual override isValidAsset(asset) returns (uint256) {
        revert("Method not yet implemented");
    }

    function notifyFinalized(address pool, bytes32 uuid) external override isValidVaultManager(msg.sender) isValidLiquidityPool(pool) {
        revert("Method not yet implemented");
    }
}
