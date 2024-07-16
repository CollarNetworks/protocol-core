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

    // collar lengths

    /// @notice Adds a collar length to the list of supported collar lengths
    /// @param duration The length to add, in seconds
    function addCollarDuration(uint duration) external;

    /// @notice Removes a collar duration from the list of supported collar lengths
    /// @param duration The length to remove, in seconds
    function removeCollarDuration(uint duration) external;

    // ltvs

    /// @notice Adds an LTV to the list of supported LTVs
    /// @param ltv The LTV to add, in basis points
    function addLTV(uint ltv) external;

    /// @notice Removes an LTV from the list of supported LTVs
    /// @param ltv The LTV to remove, in basis points
    function removeLTV(uint ltv) external;

    // ----- view functions

    // cash assets

    /// @notice Checks if an asset is supported as a cash asset in the engine
    /// @param asset The address of the asset to check
    function isSupportedCashAsset(address asset) external view returns (bool);

    /// @notice Gets the number of supported cash assets in the engine
    function supportedCashAssetsLength() external view returns (uint);

    /// @notice Gets the address of a supported cash asset at a particular index
    /// @param index The index of the asset to get the address of
    function getSupportedCashAsset(uint index) external view returns (address);

    // collateral assets

    /// @notice Checks if an asset is supported as a collateral asset in the engine
    /// @param asset The address of the asset to check
    function isSupportedCollateralAsset(address asset) external view returns (bool);

    /// @notice Gets the number of supported collateral assets in the engine
    function supportedCollateralAssetsLength() external view returns (uint);

    /// @notice Gets the address of a supported collateral asset at a particular index
    function getSupportedCollateralAsset(uint index) external view returns (address);

    // collar durations

    /// @notice Checks to see if a particular collar duration is supported
    /// @param duration The duration to check
    function isValidCollarDuration(uint duration) external view returns (bool);

    /// @notice Gets the number of supported collar lengths in the engine
    function validCollarDurationsLength() external view returns (uint);

    /// @notice Gets the collar duration at a particular index
    /// @param index The index of the collar duration to get
    function getValidCollarDuration(uint index) external view returns (uint);

    // ltvs

    /// @notice Checks to see if a particular LTV is supported
    /// @param ltv The LTV to check
    function isValidLTV(uint ltv) external view returns (bool);

    /// @notice Gets the number of supported LTVs in the engine
    function validLTVsLength() external view returns (uint);

    /// @notice Gets the LTV at a particular index
    /// @param index The index of the LTV to get
    function getValidLTV(uint index) external view returns (uint);

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
