// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ICollarEngine } from "../interfaces/ICollarEngine.sol";
import { ICollarEngineEvents } from "../interfaces/events/ICollarEngineEvents.sol";
import { CollarPool } from "./CollarPool.sol";
import { CollarVaultManager } from "./CollarVaultManager.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { CollarOracle } from "../libs/CollarLibs.sol";
import { IPeripheryImmutableState } from "@uni-v3-periphery/interfaces/IPeripheryImmutableState.sol";
import "forge-std/console.sol";

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

        emit VaultManagerCreated(vaultManager, msg.sender);

        return vaultManager;
    }

    // liquidity pools

    function addLiquidityPool(address pool) external override onlyOwner ensureLiquidityPoolIsNotValid(pool) {
        emit LiquidityPoolAdded(pool);
        collarLiquidityPools.add(pool);
    }

    function removeLiquidityPool(address pool) external override onlyOwner ensureLiquidityPoolIsValid(pool) {
        emit LiquidityPoolRemoved(pool);
        collarLiquidityPools.remove(pool);
    }

    // collateral assets

    function addSupportedCollateralAsset(address asset) external override onlyOwner ensureCollateralAssetIsNotValid(asset) {
        emit CollateralAssetAdded(asset);
        supportedCollateralAssets.add(asset);
    }

    function removeSupportedCollateralAsset(address asset) external override onlyOwner ensureCollateralAssetIsValid(asset) {
        emit CollateralAssetRemoved(asset);
        supportedCollateralAssets.remove(asset);
    }

    // cash assets

    function addSupportedCashAsset(address asset) external override onlyOwner ensureCashAssetIsNotValid(asset) {
        emit CashAssetAdded(asset);
        supportedCashAssets.add(asset);
    }

    function removeSupportedCashAsset(address asset) external override onlyOwner ensureCashAssetIsValid(asset) {
        emit CashAssetRemoved(asset);
        supportedCashAssets.remove(asset);
    }

    // durations

    function addCollarDuration(uint256 duration) external override onlyOwner ensureDurationIsNotValid(duration) {
        emit CollarDurationAdded(duration);
        validCollarDurations.add(duration);
    }

    function removeCollarDuration(uint256 duration) external override onlyOwner ensureDurationIsValid(duration) {
        emit CollarDurationRemoved(duration);
        validCollarDurations.remove(duration);
    }

    // ltvs

    function addLTV(uint256 ltv) external override onlyOwner ensureLTVIsNotValid(ltv) {
        emit LTVAdded(ltv);
        validLTVs.add(ltv);
    }

    function removeLTV(uint256 ltv) external override onlyOwner ensureLTVIsValid(ltv) {
        emit LTVRemoved(ltv);
        validLTVs.remove(ltv);
    }

    // ----- view functions (see ICollarEngine for documentation) -----

    // vault managers

    function isVaultManager(address vaultManager) external view override returns (bool) {
        return vaultManagers.contains(vaultManager);
    }

    function vaultManagersLength() external view override returns (uint256) {
        return vaultManagers.length();
    }

    function getVaultManager(uint256 index) external view override returns (address) {
        return vaultManagers.at(index);
    }

    // cash assets

    function isSupportedCashAsset(address asset) public view override returns (bool) {
        return supportedCashAssets.contains(asset);
    }

    function supportedCashAssetsLength() external view override returns (uint256) {
        return supportedCashAssets.length();
    }

    function getSupportedCashAsset(uint256 index) external view override returns (address) {
        return supportedCashAssets.at(index);
    }

    // collateral assets

    function isSupportedCollateralAsset(address asset) public view override returns (bool) {
        return supportedCollateralAssets.contains(asset);
    }

    function supportedCollateralAssetsLength() external view override returns (uint256) {
        return supportedCollateralAssets.length();
    }

    function getSupportedCollateralAsset(uint256 index) external view override returns (address) {
        return supportedCollateralAssets.at(index);
    }

    // liquidity pools

    function isSupportedLiquidityPool(address pool) external view override returns (bool) {
        return collarLiquidityPools.contains(pool);
    }

    function supportedLiquidityPoolsLength() external view override returns (uint256) {
        return collarLiquidityPools.length();
    }

    function getSupportedLiquidityPool(uint256 index) external view override returns (address) {
        return collarLiquidityPools.at(index);
    }

    // collar durations

    function isValidCollarDuration(uint256 duration) external view override returns (bool) {
        return validCollarDurations.contains(duration);
    }

    function validCollarDurationsLength() external view override returns (uint256) {
        return validCollarDurations.length();
    }

    function getValidCollarDuration(uint256 index) external view override returns (uint256) {
        return validCollarDurations.at(index);
    }

    // ltvs

    function isValidLTV(uint256 ltv) external view override returns (bool) {
        return validLTVs.contains(ltv);
    }

    function validLTVsLength() external view override returns (uint256) {
        return validLTVs.length();
    }

    function getValidLTV(uint256 index) external view override returns (uint256) {
        return validLTVs.at(index);
    }

    // asset pricing

    function validateAssetsIsSupported(address token) internal view {
        bool isSupportedBase = isSupportedCashAsset(token) || isSupportedCollateralAsset(token);
        if (!isSupportedBase) revert CollateralAssetNotSupported(token);
    }

    function getHistoricalAssetPriceViaTWAP(address baseToken, address quoteToken, uint32 twapStartTimestamp, uint32 twapLength)
        external
        view
        virtual
        override
        returns (uint256 price)
    {
        validateAssetsIsSupported(baseToken);
        validateAssetsIsSupported(quoteToken);
        address uniV3Factory = IPeripheryImmutableState(dexRouter).factory();
        console.log("uniV3Factory: ", uniV3Factory);
        price = CollarOracle.getTWAP(baseToken, quoteToken, twapStartTimestamp, twapLength, uniV3Factory);
    }

    function getCurrentAssetPrice(address baseToken, address quoteToken) external view virtual override returns (uint256 price) {
        validateAssetsIsSupported(baseToken);
        validateAssetsIsSupported(quoteToken);
        address uniV3Factory = IPeripheryImmutableState(dexRouter).factory();
        console.log("uniV3Factory: ", uniV3Factory);
        /**
         * @dev pass in 0,0 to get price at current tick
         */
        price = CollarOracle.getTWAP(baseToken, quoteToken, 0, 0, uniV3Factory);
    }
}

/**
 * Vault expiration timestamp:  1713267958
 *   Current timestamp:  1713440758
 *   Offset calculated as  173700
 *   Computed pool address:  0x2DB87C4831B2fec2E35591221455834193b50D1B
 *   baseToken is  0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
 *   quoteToken is  0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
 *   timeStampStart is  1713267958
 *   twapLength is  900
 *   Amount baseToken received for 1e18 quoteToken:  741201
 */
