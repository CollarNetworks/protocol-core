// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

abstract contract ICollarEngineErrors {
    error VaultManagerAlreadyExists(address user, address vaultManager);
    error LiquidityPoolAlreadyAdded(address pool);
    error CollateralAssetNotSupported(address asset);
    error CashAssetNotSupported(address asset);
    error CollateralAssetAlreadySupported(address asset);
    error CashAssetAlreadySupported(address asset);
    error InvalidZeroAddress(address addr);
    error InvalidCashAmount(uint256 amount);
    error InvalidCollateralAmount(uint256 amount);
    error InvalidLiquidityPool(address pool);
    error CollarLengthNotSupported(uint256 length);
    error InvalidLiquidityOpts();
    error AssetNotSupported(address asset);
    error AssetAlreadySupported(address asset);
}

abstract contract ICollarEngine is ICollarEngineErrors {

    address public immutable dexRouter;

    modifier isValidLiquidityPool(address pool) {
        if (!isLiquidityPool[pool]) revert InvalidLiquidityPool(pool);
        _;
    }

    modifier isNotValidLiquidityPool(address pool) {
        if (isLiquidityPool[pool]) revert LiquidityPoolAlreadyAdded(pool);
        _;
    }

    modifier isValidCollateralAsset(address asset) {
        if (!isSupportedCollateralAsset[asset]) revert CollateralAssetNotSupported(asset);
        _;
    }

    modifier isValidCashAsset(address asset) {
        if (!isSupportedCashAsset[asset]) revert CashAssetNotSupported(asset);
        _;
    }

    modifier isValidAsset(address asset) {
        if (!isSupportedCollateralAsset[asset] && !isSupportedCashAsset[asset]) revert AssetNotSupported(asset);
        _;
    }

    modifier isNotValidCollateralAsset(address asset) {
        if (isSupportedCollateralAsset[asset]) revert CollateralAssetAlreadySupported(asset);
        _;
    }

    modifier isNotValidCashAsset(address asset) {
        if (isSupportedCashAsset[asset]) revert CashAssetAlreadySupported(asset);
        _;
    }

    modifier isNotValidAsset(address asset) {
        if (isSupportedCollateralAsset[asset] || isSupportedCashAsset[asset]) revert AssetAlreadySupported(asset);
        _;
    }

    modifier isSupportedCollarLength(uint256 length) {
        if (!isValidCollarLength[length]) revert CollarLengthNotSupported(length);
        _;
    }

    modifier isNotSupportedCollarLength(uint256 length) {
        if (isValidCollarLength[length]) revert CollarLengthNotSupported(length);
        _;
    }

    /// @notice This mapping stores the address of the vault contract per user (or market maker)
    /// @dev This will be zero if the user has not yet created a vault
    mapping(address => address) public addressToVaultManager;

    /// @notice This mapping indicates whether or not a particular pool is valid
    mapping(address => bool) public isLiquidityPool;

    /// @notice This mapping indicates whether or not a particular asset is supported as collateral
    mapping(address => bool) public isSupportedCollateralAsset;

    /// @notice This mapping indicates whether or not a particular asset is supported as cash
    mapping(address => bool) public isSupportedCashAsset;

    /// @notice This mapping indicates whether or not a particular collar length is supported
    mapping(uint256 => bool) public isValidCollarLength;
    
    /// @notice Initializes the engine.
    constructor(address _dexRouter) {
        dexRouter = _dexRouter;
    }

    /// @notice Adds a liquidity pool to the list of supported pools
    /// @param pool The address of the pool to add
    function addLiquidityPool(address pool) external virtual;

    /// @notice Removes a liquidity pool from the list of supported pools
    /// @param pool The address of the pool to remove
    function removeLiquidityPool(address pool) external virtual;

    /// @notice Creates a vault manager contract for the user that calls this function, if it does not already exist
    /// @dev This function is called by the user when they want to create a new vault if they haven't done so in the past
    function createVaultManager() external virtual returns (address);
    
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
    function addSupportedCollarLength(uint256 length) external virtual;

    /// @notice Removes a collar length from the list of supported collar lengths
    /// @param length The length to remove, in seconds
    function removeSupportedCollarLength(uint256 length) external virtual;

    /// @notice Gets the price of a particular asset at a particular timestamp
    /// @param asset The address of the asset to get the price of
    /// @param timestamp The timestamp to get the price at
    function getHistoricalAssetPrice(address asset, uint256 timestamp) external view virtual returns (uint256);

    /// @notice Gets the current price of 1e18 of a particular asset
    /// @param asset The address of the asset to get the price of
    function getCurrentAssetPrice(address asset) external view virtual returns (uint256);

    /// @notice Allows a valid vault to notify the pool that it is finalized
    /// @param liquidityPool The address of the liquidity pool
    /// @param uuid The UUID of the vault to finalize
    function notifyFinalized(address liquidityPool, bytes32 uuid) external virtual;
}