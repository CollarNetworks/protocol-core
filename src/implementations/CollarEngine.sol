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
import { IStaticOracle } from "@mean-finance/interfaces/IStaticOracle.sol";
import "forge-std/console.sol";

contract CollarEngine is ICollarEngine, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    constructor(address _dexRouter, address _staticOracle) ICollarEngine(_dexRouter, _staticOracle) Ownable(msg.sender) { }

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

    function isSupportedCashAsset(address asset) external view override returns (bool) {
        return supportedCashAssets.contains(asset);
    }

    function supportedCashAssetsLength() external view override returns (uint256) {
        return supportedCashAssets.length();
    }

    function getSupportedCashAsset(uint256 index) external view override returns (address) {
        return supportedCashAssets.at(index);
    }

    // collateral assets

    function isSupportedCollateralAsset(address asset) external view override returns (bool) {
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

    function getHistoricalAssetPriceViaTWAP(address baseToken, address quoteToken, uint32 twapEndTimestamp, uint32 twapLength)
        external
        view
        virtual
        override
        returns (uint256)
    {
        // @TODO replace this with parameter data
        uint24[] memory feeTiers = new uint24[](1);
        feeTiers[0] = 3000;

        // Calculate *how long ago* the timestamp passed in as a parameter is,
        // so that we can use this in the "offset" part
        // First, we calculate what the offset is to the *end* of the twap (aka offset to timeStampStart)
        // THEN, we factor in the twapLength to the timestamp that we actually want to start the twap from
        uint32 offset = (uint32(block.timestamp) - twapEndTimestamp) + twapLength;
        console.log("Offset calculated as ", offset);

        (uint256 amountReceived,) = IStaticOracle(staticOracle).quoteSpecificFeeTiersWithOffsettedTimePeriod(
            1e18, // amount of token we're getting the price of
            baseToken, // token we're getting the price of
            quoteToken, // token we want to know how many of we'd get
            feeTiers, // fee tier(s) of the pool we're going to get the quote from
            twapLength, // how long the twap should be
            offset // how long ago to *start* the twap period
        );

        console.log("baseToken is ", baseToken);
        console.log("quoteToken is ", quoteToken);
        console.log("timeStampStart is ", twapEndTimestamp);
        console.log("twapLength is ", twapLength);
        console.log("Amount baseToken received for 1e18 quoteToken: ", amountReceived);

        return amountReceived;
    }

    function getCurrentAssetPrice(address /*asset*/ ) external view virtual override returns (uint256) {
        revert("Method not yet implemented");
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
