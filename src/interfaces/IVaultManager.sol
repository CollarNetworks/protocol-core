// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

abstract contract ICollarVaultManager {

    /// @notice Indicates that the vault specified does not exist
    error NonExistentVault(bytes32 vaultUUID);

    /// @notice This struct contains information about which assests (and how much of them) are in each vault
    /// @param collateralAsset The address of the collateral asset
    /// @param collateralAmount The amount of the collateral asset
    /// @param cashAsset The address of the cash asset
    /// @param cashAmount The amount of the cash asset
    struct AssetSpecifiers {
        address collateralAsset;
        uint256 collateralAmount;
        address cashAsset;
        uint256 cashAmount;
    }

    /// @notice This struct contains information about the collar options for each vault
    /// @param putStrike The strike price of the put option expressed as bps of starting price
    /// @param callStrike The strike price of the call option expressed as bps of starting price
    /// @param expiry The expiry of the options express as a unix timestamp
    /// @param ltv The maximjum loan-to-value ratio of loans taken out of this vault, expressed as bps of the collateral value
    struct CollarOpts {
        uint256 putStrike;
        uint256 callStrike;
        uint256 expiry;
        uint256 ltv;
    }

    /// @notice This struct contains information about how to source the liquidity for each vault
    /// @param liquidityPool The address of the liquidity pool to draw from
    /// @param ticks The ticks from which to draw liquidity
    /// @param amounts The amounts of liquidity to draw from each tick
    struct LiquidityOpts {
        address liquidityPool;
        uint256[] ticks;
        uint256[] amounts;
    }

    /// @notice This struct represents each individual vault as a whole
    /// @dev We use a mapping below to store each vault by unique identifier (UUID)
    /// @param collateralAmountInitial The amount of collateral deposited into the vault at the time of creation
    /// @param collateralPriceInitial The price of the collateral asset at the time of creation
    /// @param active Whether or not the vault is active (if true, it has not been finalized)
    /// @param assetSpecifiers The asset specifiers for the vault
    /// @param collarOpts The collar options for the vault
    /// @param liquidityOpts The liquidity options for the vault
    struct Vault {
        uint256 collateralAmountInitial;
        uint256 collateralPriceInitial;

        bool active;

        AssetSpecifiers assetSpecifiers;
        CollarOpts collarOpts;
        LiquidityOpts liquidityOpts;
    }

    /// @notice The user that owns the vault
    address user;

    /// @notice The number of vaults a user has opened
    uint256 public vaultCount;

    /// @notice Retrieves the vault details by UUID
    mapping(bytes32 UUID => Vault) public vaultsByUUID;

    /// @notice Gives UUID of vault by index (order of creation)
    mapping(uint256 index => bytes32 UUID) public vaultUUIDsByIndex;

    /// @notice Reverse mapping of UUID to index
    mapping(bytes32 UUID => uint256 index) public vaultIndexByUUID;

    /// @notice Whether or not the vault has been finalized (requires a transaction)
    /// @param vaultUUID The UUID of the vault to check
    function isActive(bytes32 vaultUUID) external virtual view returns (bool);

    /// @notice Whether or not the vault CAN be finalized
    /// @param vaultUUID The UUID of the vault to check
    function isExpired(bytes32 vaultUUID) external virtual view returns (bool);

    /// @notice Unix timestamp of when the vault expires (or when it expired)
    /// @param vaultUUID The UUID of the vault to check
    function getExpiry(bytes32 vaultUUID) external virtual view returns (uint256);

    /// @notice Time remaining in seconds until the vault expires - 0 if already expired
    /// @param vaultUUID The UUID of the vault to check
    function timeRemaining(bytes32 vaultUUID) external virtual view returns (uint256);

    /// @notice Allows a user to deposit cash (repay their loan) into a particular vault
    /// @param vaultUUID The UUID of the vault to deposit into
    /// @param amount The amount of cash to deposit
    /// @param from The address to send the cash from
    function depositCash(bytes32 vaultUUID, uint256 amount, address from) external virtual returns (uint256);
    
    /// @notice Allows a user to withdraw cash (take out a loan) from a particular vault
    /// @param vaultUUID The UUID of the vault to withdraw from
    /// @param amount The amount of cash to withdraw
    /// @param to The address to send the cash to
    function withrawCash(bytes32 vaultUUID, uint256 amount, address to) external virtual returns (uint256);

    /// @notice Opens a vault with the given asset specifiers and collar options and liquidity sources, if possible
    /// @dev We'll need to make sure the frontend handles all the setup here and passes in correct options
    /// @param assetSpecifiers The asset specifiers for the vault
    /// @param collarOpts The collar options for the vault
    /// @param liquidityOpts The liquidity options for the vault
    function openVault(
        AssetSpecifiers calldata assetSpecifiers,
        CollarOpts calldata collarOpts,
        LiquidityOpts calldata liquidityOpts
    ) external virtual returns (bytes32);

    /// @notice Closes a vault and returns the collateral to the user or market maker
    /// @dev This function will revert if the vault is not finalizable
    /// @param vaultUUID The UUID of the vault to close
    function finalizeVault(
        bytes32 vaultUUID
    ) external virtual returns (int256);
}