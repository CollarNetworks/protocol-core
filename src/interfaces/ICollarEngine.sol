// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

interface ICollarEngine {
    // EVENTS

    // auth'd actions
    event CollateralAssetAdded(address indexed collateralAsset);
    event CollateralAssetRemoved(address indexed collateralAsset);
    event CashAssetAdded(address indexed cashAsset);
    event CashAssetRemoved(address indexed cashAsset);
    event CollarDurationAdded(uint indexed duration);
    event CollarDurationRemoved(uint indexed duration);
    event LTVAdded(uint indexed ltv);
    event LTVRemoved(uint indexed ltv);
    event CollarTakerNFTAuthSet(address indexed contractAddress, bool indexed enabled);
    event ProviderNFTAuthSet(address indexed contractAddress, bool indexed enabled);

    // ----- state changing transactions

    // collateral assets

    /// @notice Adds an asset to the list of supported collateral assets
    /// @param asset The address of the asset to add
    function addSupportedCollateralAsset(address asset) external;

    /// @notice Removes an asset from the list of supported collateral assets
    /// @param asset The address of the asset to remove
    function removeSupportedCollateralAsset(address asset) external;

    // cash assets

    /// @notice Adds an asset to the list of supported cash assets
    /// @param asset The address of the asset to add
    function addSupportedCashAsset(address asset) external;

    /// @notice Removes an asset from the list of supported cash assets
    /// @param asset The address of the asset to remove
    function removeSupportedCashAsset(address asset) external;

    // ----- view functions

    // collar durations

    /// @notice Checks to see if a particular collar duration is supported
    /// @param duration The duration to check
    function isValidCollarDuration(uint duration) external pure returns (bool);

    // ltvs

    /// @notice Checks to see if a particular LTV is supported
    /// @param ltv The LTV to check
    function isValidLTV(uint ltv) external pure returns (bool);

    // asset pricing

    /// @notice Gets the price of a particular asset at a particular timestamp
    /// @param baseToken The address of the asset to get the price of
    /// @param quoteToken The address of the asset to quote the price in
    /// @param twapEndTimestamp The timestamp to END the TWAP at
    /// @param twapLength The length of the TWAP to calculate
    function getHistoricalAssetPriceViaTWAP(
        address baseToken,
        address quoteToken,
        uint32 twapEndTimestamp,
        uint32 twapLength
    ) external view returns (uint);
}
