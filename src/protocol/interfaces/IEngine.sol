// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

abstract contract ICollarEngineErrors {
    error VaultManagerAlreadyExists(address user, address vaultManager);
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
}

abstract contract ICollarEngine is ICollarEngineErrors {

    address public immutable dexRouter;

    modifier isValidCollateralAsset(address asset) {
        if (!isSupportedCollateralAsset[asset]) revert CollateralAssetNotSupported(asset);
        _;
    }

    modifier isValidCashAsset(address asset) {
        if (!isSupportedCashAsset[asset]) revert CashAssetNotSupported(asset);
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

    modifier isSupportedCollarLength(uint256 length) {
        if (!isValidCollarLength[length]) revert CollarLengthNotSupported(length);
        _;
    }

    modifier isNotSupportedCollarLength(uint256 length) {
        if (isValidCollarLength[length]) revert CollarLengthNotSupported(length);
        _;
    }

    address immutable core;
    address public liquidityPoolManager;

    /// @notice This mapping stores the address of the vault contract per user (or market maker)
    /// @dev This will be zero if the user has not yet created a vault
    mapping(address => address) public addressToVaultManager;

    /// @notice This mapping indicates whether or not a particular asset is supported as collateral
    mapping(address => bool) public isSupportedCollateralAsset;

    /// @notice This mapping indicates whether or not a particular asset is supported as cash
    mapping(address => bool) public isSupportedCashAsset;

    /// @notice This mapping indicates whether or not a particular collar length is supported
    mapping(uint256 => bool) public isValidCollarLength;
    
    /// @notice Initializes the engine.
    /// @param _core The address of the core contract.
    constructor(address _core, address _liquidityPoolManager, address _dexRouter) {
        core = _core;
        liquidityPoolManager = _liquidityPoolManager;
        dexRouter = _dexRouter;
    }

    /// @notice Creates a vault manager contract for the user that calls this function, if it does not already exist
    /// @dev This function is called by the user when they want to create a new vault if they haven't done so in the past
    function createVaultManager() external virtual returns (address);

    /// @notice Sets the address of the liquidity pool manager contract
    /// @param _liquidityPoolManager The address of the liquidity pool manager contract
    function setLiquidityPoolManager(address _liquidityPoolManager) external virtual;
    
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
}