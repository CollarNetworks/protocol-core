// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { IStaticOracle } from "@mean-finance/interfaces/IStaticOracle.sol";
import { ICollarEngineErrors } from "./errors/ICollarEngineErrors.sol";
import { ICollarEngineEvents } from "./events/ICollarEngineEvents.sol";

abstract contract ICollarEngine is ICollarEngineErrors, ICollarEngineEvents {
    // -- lib delcarations --
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    // -- modifiers --

    // vaults

    modifier ensureVaultManagerIsValid(address vaultManager) {
        if (vaultManagers.contains(vaultManager) == false) revert InvalidVaultManager();
        _;
    }

    modifier ensureLiquidityPoolIsValid(address pool) {
        if (!collarLiquidityPools.contains(pool)) revert InvalidLiquidityPool();
        _;
    }

    // liquidity pools

    modifier ensureLiquidityPoolIsNotValid(address pool) {
        if (collarLiquidityPools.contains(pool)) revert LiquidityPoolAlreadyAdded(pool);
        _;
    }

    // collateral assets

    modifier ensureCollateralAssetIsValid(address asset) {
        if (!supportedCollateralAssets.contains(asset)) revert CollateralAssetNotSupported(asset);
        _;
    }

    modifier ensureCollateralAssetIsNotValid(address asset) {
        if (supportedCollateralAssets.contains(asset)) revert CollateralAssetAlreadySupported(asset);
        _;
    }

    // cash assets

    modifier ensureCashAssetIsValid(address asset) {
        if (!supportedCashAssets.contains(asset)) revert CashAssetNotSupported(asset);
        _;
    }

    modifier ensureCashAssetIsNotValid(address asset) {
        if (supportedCashAssets.contains(asset)) revert CashAssetAlreadySupported(asset);
        _;
    }

    // collar durations

    modifier ensureDurationIsValid(uint256 duration) {
        if (!validCollarDurations.contains(duration)) revert CollarDurationNotSupported();
        _;
    }

    modifier ensureDurationIsNotValid(uint256 duration) {
        if (validCollarDurations.contains(duration)) revert CollarDurationNotSupported();
        _;
    }

    // ltvs

    modifier ensureLTVIsValid(uint256 ltv) {
        if (!validLTVs.contains(ltv)) revert LTVNotSupported(ltv);
        _;
    }

    modifier ensureLTVIsNotValid(uint256 ltv) {
        if (validLTVs.contains(ltv)) revert LTVAlreadySupported(ltv);
        _;
    }

    // -- public state variables ---

    address public immutable dexRouter;
    address public immutable uniswapV3Factory;

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

    constructor(address _dexRouter, address _uniswapV3Factory) {
        dexRouter = _dexRouter;
        uniswapV3Factory = _uniswapV3Factory;
    }

    // ----- state changing transactions

    /// @notice Creates a vault manager contract for the user that calls this function, if it does not already exist
    /// @dev This function is called by the user when they want to create a new vault if they haven't done so in the past
    function createVaultManager() external virtual returns (address);

    // liquidity pools

    /// @notice Adds a liquidity pool to the list of supported pools
    /// @param pool The address of the pool to add
    function addLiquidityPool(address pool) external virtual;

    /// @notice Removes a liquidity pool from the list of supported pools
    /// @param pool The address of the pool to remove
    function removeLiquidityPool(address pool) external virtual;

    // collateral assets

    /// @notice Adds an asset to the list of supported collateral assets
    /// @param asset The address of the asset to add
    function addSupportedCollateralAsset(address asset) external virtual;

    /// @notice Removes an asset from the list of supported collateral assets
    /// @param asset The address of the asset to remove
    function removeSupportedCollateralAsset(address asset) external virtual;

    // cash assets

    /// @notice Adds an asset to the list of supported cash assets
    /// @param asset The address of the asset to add
    function addSupportedCashAsset(address asset) external virtual;

    /// @notice Removes an asset from the list of supported cash assets
    /// @param asset The address of the asset to remove
    function removeSupportedCashAsset(address asset) external virtual;

    // collar lengths

    /// @notice Adds a collar length to the list of supported collar lengths
    /// @param duration The length to add, in seconds
    function addCollarDuration(uint256 duration) external virtual;

    /// @notice Removes a collar duration from the list of supported collar lengths
    /// @param duration The length to remove, in seconds
    function removeCollarDuration(uint256 duration) external virtual;

    // ltvs

    /// @notice Adds an LTV to the list of supported LTVs
    /// @param ltv The LTV to add, in basis points
    function addLTV(uint256 ltv) external virtual;

    /// @notice Removes an LTV from the list of supported LTVs
    /// @param ltv The LTV to remove, in basis points
    function removeLTV(uint256 ltv) external virtual;

    // ----- view functions

    // vault managers

    /// @notice Checks if an address is a vault manager
    /// @param vaultManager The address to check
    function isVaultManager(address vaultManager) external view virtual returns (bool);

    /// @notice Gets the number of vault managers in the list
    function vaultManagersLength() external view virtual returns (uint256);

    /// @notice Gets the address of a vault manager at a particular index
    /// @param index The index of the vault manager to get the address of
    function getVaultManager(uint256 index) external view virtual returns (address);

    // cash assets

    /// @notice Checks if an asset is supported as a cash asset in the engine
    /// @param asset The address of the asset to check
    function isSupportedCashAsset(address asset) external view virtual returns (bool);

    /// @notice Gets the number of supported cash assets in the engine
    function supportedCashAssetsLength() external view virtual returns (uint256);

    /// @notice Gets the address of a supported cash asset at a particular index
    /// @param index The index of the asset to get the address of
    function getSupportedCashAsset(uint256 index) external view virtual returns (address);

    // collateral assets

    /// @notice Checks if an asset is supported as a collateral asset in the engine
    /// @param asset The address of the asset to check
    function isSupportedCollateralAsset(address asset) external view virtual returns (bool);

    /// @notice Gets the number of supported collateral assets in the engine
    function supportedCollateralAssetsLength() external view virtual returns (uint256);

    /// @notice Gets the address of a supported collateral asset at a particular index
    function getSupportedCollateralAsset(uint256 index) external view virtual returns (address);

    // liquidity pools

    /// @notice Checks if a liquidity pool is supported in the engine
    /// @param pool The address of the pool to check
    function isSupportedLiquidityPool(address pool) external view virtual returns (bool);

    /// @notice Gets the number of supported liquidity pools in the engine
    function supportedLiquidityPoolsLength() external view virtual returns (uint256);

    /// @notice Gets the address of a supported liquidity pool at a particular index
    /// @param index The index of the pool to get the address of
    function getSupportedLiquidityPool(uint256 index) external view virtual returns (address);

    // collar durations

    /// @notice Checks to see if a particular collar duration is supported
    /// @param duration The duration to check
    function isValidCollarDuration(uint256 duration) external view virtual returns (bool);

    /// @notice Gets the number of supported collar lengths in the engine
    function validCollarDurationsLength() external view virtual returns (uint256);

    /// @notice Gets the collar duration at a particular index
    /// @param index The index of the collar duration to get
    function getValidCollarDuration(uint256 index) external view virtual returns (uint256);

    // ltvs

    /// @notice Checks to see if a particular LTV is supported
    /// @param ltv The LTV to check
    function isValidLTV(uint256 ltv) external view virtual returns (bool);

    /// @notice Gets the number of supported LTVs in the engine
    function validLTVsLength() external view virtual returns (uint256);

    /// @notice Gets the LTV at a particular index
    /// @param index The index of the LTV to get
    function getValidLTV(uint256 index) external view virtual returns (uint256);

    // asset pricing

    /// @notice Gets the price of a particular asset at a particular timestamp
    /// @param baseToken The address of the asset to get the price of
    /// @param quoteToken The address of the asset to quote the price in
    /// @param twapEndTimestamp The timestamp to END the TWAP at
    /// @param twapLength The length of the TWAP to calculate
    function getHistoricalAssetPriceViaTWAP(address baseToken, address quoteToken, uint32 twapEndTimestamp, uint32 twapLength)
        external
        view
        virtual
        returns (uint256);

    /// @notice Gets the current price of 1e18 of a particular asset
    /// @param baseToken The address of the asset to get the price of
    /// @param quoteToken The address of the asset to quote the price in
    function getCurrentAssetPrice(address baseToken, address quoteToken) external view virtual returns (uint256 price);
}
