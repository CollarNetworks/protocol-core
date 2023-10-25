// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

abstract contract ICollarEngine {
    address immutable core;
    address public liquidityPoolManager;

    /// @notice This mapping stores the address of the vault contract per user (or market maker)
    /// @dev This will be zero if the user has not yet created a vault
    mapping(address => address) public addressToVaultManager;

    /// @notice This mapping indicates whether or not a particular asset is supported as collateral
    mapping(address => bool) public isSupportedCollateralAsset;

    /// @notice This mapping indicates whether or not a particular asset is supported as cash
    mapping(address => bool) public isSupportedCashAsset;
    
    /// @notice Initializes the engine.
    /// @param _core The address of the core contract.
    constructor(address _core, address _liquidityPoolManager) {
        core = _core;
        liquidityPoolManager = _liquidityPoolManager;
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
}