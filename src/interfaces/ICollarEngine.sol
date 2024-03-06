// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ICollarEngineErrors } from "./ICollarEngineErrors.sol";

abstract contract ICollarEngine is ICollarEngineErrors {
    // -- lib delcarations --
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    // -- modifiers --
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
        if (!supportedCashAssets.contains(asset)) revert CashAssetNotSupported(asset);
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

    // -- public state variables ---

    address public immutable dexRouter;

    /// @notice todo fill me out please
    /// @dev also fill me out todo please thanks
    mapping(bytes32 uuid => bool) public isVaultFinalized;

    /// @notice This mapping stores the address of the vault contract per user (or market maker)
    /// @dev This will be zero if the user has not yet created a vault
    mapping(address => address) public addressToVaultManager;

    // -- internal state variables ---
    EnumerableSet.AddressSet internal vaultManagers;
    EnumerableSet.AddressSet internal collarLiquidityPools;
    EnumerableSet.AddressSet internal supportedCollateralAssets;
    EnumerableSet.AddressSet internal supportedCashAssets;
    EnumerableSet.UintSet internal validCollarLengths;

    constructor(address _dexRouter) {
        dexRouter = _dexRouter;
    }

    // ----- state changing transactions

    /// @notice Creates a vault manager contract for the user that calls this function, if it does not already exist
    /// @dev This function is called by the user when they want to create a new vault if they haven't done so in the past
    function createVaultManager() external virtual returns (address);

    /// @notice Adds a liquidity pool to the list of supported pools
    /// @param pool The address of the pool to add
    function addLiquidityPool(address pool) external virtual;

    /// @notice Removes a liquidity pool from the list of supported pools
    /// @param pool The address of the pool to remove
    function removeLiquidityPool(address pool) external virtual;

    /// @notice Adds an asset to the list of supported collateral assets
    /// @param asset The address of the asset to add
    function addSupportedCollateralAsset(address asset) external virtual;

    /// @notice Removes an asset from the list of supported collateral assets
    /// @param asset The address of the asset to remove
    function removeSupportedCollateralAsset(address asset) external virtual;

    /// @notice Adds an asset to the list of supported cash assets
    /// @param asset The address of the asset to add
    function addSupportedCashAsset(address asset) external virtual;

    /// @notice Removes an asset from the list of supported cash assets
    /// @param asset The address of the asset to remove
    function removeSupportedCashAsset(address asset) external virtual;

    /// @notice Adds a collar length to the list of supported collar lengths
    /// @param length The length to add, in seconds
    function addCollarLength(uint256 length) external virtual;

    /// @notice Removes a collar length from the list of supported collar lengths
    /// @param length The length to remove, in seconds
    function removeCollarLength(uint256 length) external virtual;

    // ----- view functions

    /// @notice Checks if an address is a vault manager
    /// @param vaultManager The address to check
    function isVaultManager(address vaultManager) external view virtual returns (bool);

    /// @notice Gets the number of vault managers in the list
    function vaultManagersLength() external view virtual returns (uint256);

    /// @notice Gets the address of a vault manager at a particular index
    /// @param index The index of the vault manager to get the address of
    function getVaultManager(uint256 index) external view virtual returns (address);

    /// @notice Gets the price of a particular asset at a particular timestamp
    /// @param asset The address of the asset to get the price of
    /// @param timestamp The timestamp to get the price at
    function getHistoricalAssetPrice(address asset, uint256 timestamp) external view virtual returns (uint256);

    /// @notice Gets the current price of 1e18 of a particular asset
    /// @param asset The address of the asset to get the price of
    function getCurrentAssetPrice(address asset) external view virtual returns (uint256);

    /// @notice Checks if an asset is supported as a cash asset in the engine
    /// @param asset The address of the asset to check
    function isSupportedCashAsset(address asset) external view virtual returns (bool);

    /// @notice Gets the number of supported cash assets in the engine
    function supportedCashAssetsLength() external view virtual returns (uint256);

    /// @notice Gets the address of a supported cash asset at a particular index
    /// @param index The index of the asset to get the address of
    function getSupportedCashAsset(uint256 index) external view virtual returns (address);

    /// @notice Checks if an asset is supported as a collateral asset in the engine
    /// @param asset The address of the asset to check
    function isSupportedCollateralAsset(address asset) external view virtual returns (bool);

    /// @notice Gets the number of supported collateral assets in the engine
    function supportedCollateralAssetsLength() external view virtual returns (uint256);

    /// @notice Gets the address of a supported collateral asset at a particular index
    function getSupportedCollateralAsset(uint256 index) external view virtual returns (address);

    /// @notice Checks if a liquidity pool is supported in the engine
    /// @param pool The address of the pool to check
    function isSupportedLiquidityPool(address pool) external view virtual returns (bool);

    /// @notice Gets the number of supported liquidity pools in the engine
    function supportedLiquidityPoolsLength() external view virtual returns (uint256);

    /// @notice Gets the address of a supported liquidity pool at a particular index
    /// @param index The index of the pool to get the address of
    function getSupportedLiquidityPool(uint256 index) external view virtual returns (address);

    /// @notice Checks to see if a particular collar length is supported
    /// @param length The length to check
    function isValidCollarLength(uint256 length) external view virtual returns (bool);

    /// @notice Gets the number of supported collar lengths in the engine
    function validCollarLengthsLength() external view virtual returns (uint256);

    /// @notice Gets the collar length at a particular index
    /// @param index The index of the collar length to get
    function getValidCollarLength(uint256 index) external view virtual returns (uint256);
}
