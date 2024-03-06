// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarEngine } from "../interfaces/ICollarEngine.sol";
import { CollarPool } from "./CollarPool.sol";
import { CollarVaultManager } from "./CollarVaultManager.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract CollarEngine is ICollarEngine, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    constructor(address _dexRouter) ICollarEngine(_dexRouter) Ownable(msg.sender) { }

    // ----- state-changing functions (see ICollarEngine for documentation) -----

    function createVaultManager() external override returns (address _vaultManager) {
        if (addressToVaultManager[msg.sender] != address(0)) {
            revert VaultManagerAlreadyExists(msg.sender, addressToVaultManager[msg.sender]);
        }

        address vaultManager = address(new CollarVaultManager(address(this), msg.sender));

        vaultManagers.add(vaultManager);
        addressToVaultManager[msg.sender] = vaultManager;

        return vaultManager;
    }

    function addLiquidityPool(address pool) external override onlyOwner ensureNotValidLiquidityPool(pool) {
        collarLiquidityPools.add(pool);
    }

    function removeLiquidityPool(address pool) external override onlyOwner ensureValidLiquidityPool(pool) {
        collarLiquidityPools.remove(pool);
    }

    function addSupportedCollateralAsset(address asset) external override onlyOwner ensureNotValidCollateralAsset(asset) {
        supportedCollateralAssets.add(asset);
    }

    function removeSupportedCollateralAsset(address asset) external override onlyOwner ensureValidCollateralAsset(asset) {
        supportedCollateralAssets.remove(asset);
    }

    function addSupportedCashAsset(address asset) external override onlyOwner ensureNotValidCashAsset(asset) {
        supportedCashAssets.add(asset);
    }

    function removeSupportedCashAsset(address asset) external override onlyOwner ensureValidCashAsset(asset) {
        supportedCashAssets.remove(asset);
    }

    function addCollarLength(uint256 length) external override onlyOwner ensureNotSupportedCollarLength(length) {
        validCollarLengths.add(length);
    }

    function removeCollarLength(uint256 length) external override onlyOwner ensureSupportedCollarLength(length) {
        validCollarLengths.remove(length);
    }

    function notifyFinalized(address pool, bytes32 uuid) external override ensureValidVaultManager(msg.sender) {
        isVaultFinalized[uuid] = true;

        CollarPool(pool).finalizeToken(uuid);
    }

    // ----- view functions (see ICollarEngine for documentation) -----

    function isVaultManager(address vaultManager) external view override returns (bool) {
        return vaultManagers.contains(vaultManager);
    }

    function vaultManagersLength() external view override returns (uint256) {
        return vaultManagers.length();
    }

    function getVaultManager(uint256 index) external view override returns (address) {
        return vaultManagers.at(index);
    }

    function getHistoricalAssetPrice(address, /*asset*/ uint256 /*timestamp*/ ) external view virtual override returns (uint256) {
        revert("Method not yet implemented");
    }

    function getCurrentAssetPrice(address asset) external view virtual override ensureValidAsset(asset) returns (uint256) {
        revert("Method not yet implemented");
    }

    function isSupportedCashAsset(address asset) external view override returns (bool) {
        return supportedCashAssets.contains(asset);
    }

    function supportedCashAssetsLength() external view override returns (uint256) {
        return supportedCashAssets.length();
    }

    function getSupportedCashAsset(uint256 index) external view override returns (address) {
        return supportedCashAssets.at(index);
    }

    function isSupportedCollateralAsset(address asset) external view override returns (bool) {
        return supportedCollateralAssets.contains(asset);
    }

    function supportedCollateralAssetsLength() external view override returns (uint256) {
        return supportedCollateralAssets.length();
    }

    function getSupportedCollateralAsset(uint256 index) external view override returns (address) {
        return supportedCollateralAssets.at(index);
    }

    function isSupportedLiquidityPool(address pool) external view override returns (bool) {
        return collarLiquidityPools.contains(pool);
    }

    function supportedLiquidityPoolsLength() external view override returns (uint256) {
        return collarLiquidityPools.length();
    }

    function getSupportedLiquidityPool(uint256 index) external view override returns (address) {
        return collarLiquidityPools.at(index);
    }

    function isValidCollarLength(uint256 length) external view override returns (bool) {
        return validCollarLengths.contains(length);
    }

    function validCollarLengthsLength() external view override returns (uint256) {
        return validCollarLengths.length();
    }

    function getValidCollarLength(uint256 index) external view override returns (uint256) {
        return validCollarLengths.at(index);
    }
}
