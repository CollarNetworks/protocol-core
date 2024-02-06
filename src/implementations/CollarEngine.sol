// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarEngine } from "../interfaces/ICollarEngine.sol";
import { CollarVaultManager } from "./CollarVaultManager.sol";
import { CollarPool } from "./CollarPool.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract CollarEngine is ICollarEngine, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    modifier ensureValidVaultManager(address vaultManager) {
        if (vaultManagers.contains(vaultManager) == false) revert InvalidVaultManager(vaultManager);
        _;
    }

    modifier ensureValidLiquidityPool(address pool) {
        if (!collarLiquidityPools.contains(pool)) revert InvalidLiquidityPool(pool);
        _;
    }

    modifier ensureNotValidLiquidityPool(address pool) {
        if (collarLiquidityPools.contains(pool)) revert LiquidityPoolAlreadyAdded(pool);
        _;
    }

    modifier ensureValidCollateralAsset(address asset) {
        if (!supportedCollateralAssets.contains(asset)) revert CollateralAssetNotSupported(asset);
        _;
    }

    modifier ensureValidCashAsset(address asset) {
        if (!supportedCollateralAssets.contains(asset)) revert CashAssetNotSupported(asset);
        _;
    }

    modifier ensureValidAsset(address asset) {
        if (!supportedCashAssets.contains(asset) && !supportedCollateralAssets.contains(asset)) revert AssetNotSupported(asset);
        _;
    }

    modifier ensureNotValidCollateralAsset(address asset) {
        if (supportedCollateralAssets.contains(asset)) revert CollateralAssetAlreadySupported(asset);
        _;
    }

    modifier ensureNotValidCashAsset(address asset) {
        if (supportedCashAssets.contains(asset)) revert CashAssetAlreadySupported(asset);
        _;
    }

    modifier ensureNotValidAsset(address asset) {
        if (supportedCollateralAssets.contains(asset) || supportedCashAssets.contains(asset)) revert AssetAlreadySupported(asset);
        _;
    }

    modifier ensureSupportedCollarLength(uint256 length) {
        if (!validCollarLengths.contains(length)) revert CollarLengthNotSupported(length);
        _;
    }

    modifier ensureNotSupportedCollarLength(uint256 length) {
        if (validCollarLengths.contains(length)) revert CollarLengthNotSupported(length);
        _;
    }

    EnumerableSet.AddressSet internal vaultManagers;
    EnumerableSet.AddressSet internal collarLiquidityPools;
    EnumerableSet.AddressSet internal supportedCollateralAssets;
    EnumerableSet.AddressSet internal supportedCashAssets;
    EnumerableSet.UintSet internal validCollarLengths;
    
    mapping(bytes32 uuid => bool) public isVaultFinalized;

    constructor(address _dexRouter) ICollarEngine(_dexRouter) Ownable(msg.sender) { }

    function isVaultManager(address vaultManager) external view returns (bool) {
        return vaultManagers.contains(vaultManager);
    }

    function vaultManagersLength() external view returns (uint256) {
        return vaultManagers.length();
    }

    function getVaultManager(uint256 index) external view returns (address) {
        return vaultManagers.at(index);
    }

    function isSupportedCashAsset(address asset) external view returns (bool) {
        return supportedCashAssets.contains(asset);
    }

    function supportedCashAssetsLength() external view returns (uint256) {
        return supportedCashAssets.length();
    }

    function getSupportedCashAsset(uint256 index) external view returns (address) {
        return supportedCashAssets.at(index);
    }

    function isSupportedCollateralAsset(address asset) external view returns (bool) {
        return supportedCollateralAssets.contains(asset);
    }

    function supportedCollateralAssetsLength() external view returns (uint256) {
        return supportedCollateralAssets.length();
    }

    function getSupportedCollateralAsset(uint256 index) external view returns (address) {
        return supportedCollateralAssets.at(index);
    }

    function isSupportedLiquidityPool(address pool) external view returns (bool) {
        return collarLiquidityPools.contains(pool);
    }

    function supportedLiquidityPoolsLength() external view returns (uint256) {
        return collarLiquidityPools.length();
    }

    function getSupportedLiquidityPool(uint256 index) external view returns (address) {
        return collarLiquidityPools.at(index);
    }

    function isValidCollarLength(uint256 length) external view returns (bool) {
        return validCollarLengths.contains(length);
    }

    function validCollarLengthsLength() external view returns (uint256) {
        return validCollarLengths.length();
    }

    function getValidCollarLength(uint256 index) external view returns (uint256) {
        return validCollarLengths.at(index);
    }

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

    function getHistoricalAssetPrice(address, /*asset*/ uint256 /*timestamp*/ ) external view virtual override returns (uint256) {
        revert("Method not yet implemented");
    }

    function getCurrentAssetPrice(address asset) external view virtual override ensureValidAsset(asset) returns (uint256) {
        revert("Method not yet implemented");
    }

    function notifyFinalized(address pool, bytes32 uuid) external override ensureValidVaultManager(msg.sender) {
        isVaultFinalized[uuid] = true;

        CollarPool(pool).finalizeToken(uuid);
    }
}
