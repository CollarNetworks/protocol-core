// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IPeripheryImmutableState } from "@uni-v3-periphery/interfaces/IPeripheryImmutableState.sol";
// internal imports
import { ICollarEngine } from "../interfaces/ICollarEngine.sol";
import { CollarPool } from "./CollarPool.sol";
import { CollarVaultManager } from "./CollarVaultManager.sol";
import { CollarOracleLib } from "../libs/CollarOracleLib.sol";

import "forge-std/console.sol";

contract CollarEngine is Ownable, ICollarEngine {
    // -- lib delcarations --
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    // -- public state variables ---

    address public immutable dexRouter;

    /// @notice This mapping stores the address of the vault contract per user (or market maker)
    /// @dev This will be zero if the user has not yet created a vault
    mapping(address => address) public addressToVaultManager;

    // -- internal state variables ---
    EnumerableSet.AddressSet internal vaultManagers;
    EnumerableSet.AddressSet internal collarLiquidityPools;
    EnumerableSet.AddressSet internal supportedCollateralAssets;
    EnumerableSet.AddressSet internal supportedCashAssets;
    EnumerableSet.UintSet internal validLTVs;
    EnumerableSet.UintSet internal validCollarDurations;

    constructor(address _dexRouter) Ownable(msg.sender) {
        dexRouter = _dexRouter;
    }

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

    function addLiquidityPool(address pool) external override onlyOwner {
        if (collarLiquidityPools.contains(pool)) revert LiquidityPoolAlreadyAdded(pool);
        collarLiquidityPools.add(pool);
        emit LiquidityPoolAdded(pool);
    }

    function removeLiquidityPool(address pool) external override onlyOwner {
        if (!collarLiquidityPools.contains(pool)) revert InvalidLiquidityPool();
        collarLiquidityPools.remove(pool);
        emit LiquidityPoolRemoved(pool);
    }

    // collateral assets

    function addSupportedCollateralAsset(address asset) external override onlyOwner {
        if (supportedCollateralAssets.contains(asset)) revert CollateralAssetAlreadySupported(asset);
        supportedCollateralAssets.add(asset);
        emit CollateralAssetAdded(asset);
    }

    function removeSupportedCollateralAsset(address asset) external override onlyOwner {
        if (!supportedCollateralAssets.contains(asset)) revert CollateralAssetNotSupported(asset);
        supportedCollateralAssets.remove(asset);
        emit CollateralAssetRemoved(asset);
    }

    // cash assets

    function addSupportedCashAsset(address asset) external override onlyOwner {
        if (supportedCashAssets.contains(asset)) revert CashAssetAlreadySupported(asset);
        supportedCashAssets.add(asset);
        emit CashAssetAdded(asset);
    }

    function removeSupportedCashAsset(address asset) external override onlyOwner {
        if (!supportedCashAssets.contains(asset)) revert CashAssetNotSupported(asset);
        supportedCashAssets.remove(asset);
        emit CashAssetRemoved(asset);
    }

    // durations

    function addCollarDuration(uint duration) external override onlyOwner {
        if (validCollarDurations.contains(duration)) revert CollarDurationNotSupported();
        validCollarDurations.add(duration);
        emit CollarDurationAdded(duration);
    }

    function removeCollarDuration(uint duration) external override onlyOwner {
        if (!validCollarDurations.contains(duration)) revert CollarDurationNotSupported();
        validCollarDurations.remove(duration);
        emit CollarDurationRemoved(duration);
    }

    // ltvs

    function addLTV(uint ltv) external override onlyOwner {
        if (validLTVs.contains(ltv)) revert LTVAlreadySupported(ltv);
        validLTVs.add(ltv);
        emit LTVAdded(ltv);
    }

    function removeLTV(uint ltv) external override onlyOwner {
        if (!validLTVs.contains(ltv)) revert LTVNotSupported(ltv);
        validLTVs.remove(ltv);
        emit LTVRemoved(ltv);
    }

    // ----- view functions (see ICollarEngine for documentation) -----

    // vault managers

    function isVaultManager(address vaultManager) external view override returns (bool) {
        return vaultManagers.contains(vaultManager);
    }

    function vaultManagersLength() external view override returns (uint) {
        return vaultManagers.length();
    }

    function getVaultManager(uint index) external view override returns (address) {
        return vaultManagers.at(index);
    }

    // cash assets

    function isSupportedCashAsset(address asset) public view override returns (bool) {
        return supportedCashAssets.contains(asset);
    }

    function supportedCashAssetsLength() external view override returns (uint) {
        return supportedCashAssets.length();
    }

    function getSupportedCashAsset(uint index) external view override returns (address) {
        return supportedCashAssets.at(index);
    }

    // collateral assets

    function isSupportedCollateralAsset(address asset) public view override returns (bool) {
        return supportedCollateralAssets.contains(asset);
    }

    function supportedCollateralAssetsLength() external view override returns (uint) {
        return supportedCollateralAssets.length();
    }

    function getSupportedCollateralAsset(uint index) external view override returns (address) {
        return supportedCollateralAssets.at(index);
    }

    // liquidity pools

    function isSupportedLiquidityPool(address pool) external view override returns (bool) {
        return collarLiquidityPools.contains(pool);
    }

    function supportedLiquidityPoolsLength() external view override returns (uint) {
        return collarLiquidityPools.length();
    }

    function getSupportedLiquidityPool(uint index) external view override returns (address) {
        return collarLiquidityPools.at(index);
    }

    // collar durations

    function isValidCollarDuration(uint duration) external view override returns (bool) {
        return validCollarDurations.contains(duration);
    }

    function validCollarDurationsLength() external view override returns (uint) {
        return validCollarDurations.length();
    }

    function getValidCollarDuration(uint index) external view override returns (uint) {
        return validCollarDurations.at(index);
    }

    // ltvs

    function isValidLTV(uint ltv) external view override returns (bool) {
        return validLTVs.contains(ltv);
    }

    function validLTVsLength() external view override returns (uint) {
        return validLTVs.length();
    }

    function getValidLTV(uint index) external view override returns (uint) {
        return validLTVs.at(index);
    }

    // asset pricing

    function validateAssetsIsSupported(address token) internal view {
        bool isSupportedBase = isSupportedCashAsset(token) || isSupportedCollateralAsset(token);
        if (!isSupportedBase) revert CollateralAssetNotSupported(token);
    }

    function getHistoricalAssetPriceViaTWAP(
        address baseToken,
        address quoteToken,
        uint32 twapStartTimestamp,
        uint32 twapLength
    )
        external
        view
        virtual
        override
        returns (uint price)
    {
        validateAssetsIsSupported(baseToken);
        validateAssetsIsSupported(quoteToken);
        address uniV3Factory = IPeripheryImmutableState(dexRouter).factory();
        price = CollarOracleLib.getTWAP(baseToken, quoteToken, twapStartTimestamp, twapLength, uniV3Factory);
    }

    function getCurrentAssetPrice(
        address baseToken,
        address quoteToken
    )
        external
        view
        virtual
        override
        returns (uint price)
    {
        validateAssetsIsSupported(baseToken);
        validateAssetsIsSupported(quoteToken);
        address uniV3Factory = IPeripheryImmutableState(dexRouter).factory();
        /**
         * @dev pass in 0,0 to get price at current tick
         */
        price = CollarOracleLib.getTWAP(baseToken, quoteToken, 0, 0, uniV3Factory);
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
