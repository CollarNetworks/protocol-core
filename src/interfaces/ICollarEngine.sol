// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

interface ICollarEngine {
    // EVENTS

    // auth'd actions
    event CollateralAssetSupportSet(address indexed collateralAsset, bool indexed enabled);
    event CashAssetSupportSet(address indexed cashAsset, bool indexed enabled);
    event LTVRangeSet(uint indexed minLTV, uint indexed maxLTV);
    event CollarDurationRangeSet(uint indexed minDuration, uint indexed maxDuration);
    event CollarTakerNFTAuthSet(
        address indexed contractAddress, bool indexed enabled, address cashAsset, address collateralAsset
    );
    event ProviderNFTAuthSet(
        address indexed contractAddress,
        bool indexed enabled,
        address cashAsset,
        address collateralAsset,
        address collarTakerNFT
    );

    // ----- state changing transactions

    // ltv

    /// @notice Sets the LTV minimum and max values for the engine
    /// @param minLTV The new minimum LTV
    /// @param maxLTV The new maximum LTV
    function setLTVRange(uint minLTV, uint maxLTV) external;

    // collar durations

    /// @notice Sets the minimum and maximum collar durations for the engine
    /// @param minDuration The new minimum collar duration
    /// @param maxDuration The new maximum collar duration
    function setCollarDurationRange(uint minDuration, uint maxDuration) external;

    // collateral assets

    /// @notice Sets whether a particular collateral asset is supported
    /// @param collateralAsset The address of the collateral asset
    /// @param enabled Whether the asset is supported
    function setCollateralAssetSupport(address collateralAsset, bool enabled) external;

    // cash assets

    /// @notice Sets whether a particular cash asset is supported
    /// @param cashAsset The address of the cash asset
    /// @param enabled Whether the asset is supported
    function setCashAssetSupport(address cashAsset, bool enabled) external;

    // ----- view functions

    // collar durations

    /// @notice Checks to see if a particular collar duration is supported
    /// @param duration The duration to check
    function isValidCollarDuration(uint duration) external view returns (bool);

    // ltvs

    /// @notice Checks to see if a particular LTV is supported
    /// @param ltv The LTV to check
    function isValidLTV(uint ltv) external view returns (bool);

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
