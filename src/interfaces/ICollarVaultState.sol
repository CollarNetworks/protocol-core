// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

/// @notice Data structures for the vault manager
interface ICollarVaultState {
    /// @notice This struct contains information about which assests (and how much of them) are in each vault
    /// @param collateralAsset The address of the collateral asset
    /// @param collateralAmount The amount of the collateral asset deposited
    /// @param cashAsset The address of the cash asset
    /// @param cashAmount The minimum amount of the cash asset to swap the collateral for
    struct AssetSpecifiers {
        address collateralAsset;
        uint256 collateralAmount;
        address cashAsset;
        uint256 cashAmount;
    }

    /// @notice This struct contains information about the collar options for each vault
    /// @param duration The length of the vault, expressed as a unix timestamp
    /// @param ltv The maximum loan-to-value ratio of loans taken out of this vault, expressed as bps of the collateral value
    struct CollarOpts {
        uint256 duration;
        uint256 ltv;
    }

    /// @notice This struct contains information about how to source the liquidity for each vault
    /// @param liquidityPool The address of the liquidity pool to draw from
    /// @param tick The tick at which liquidity is locked
    struct LiquidityOpts {
        address liquidityPool;
        uint24 putStrikeTick;
        uint24 callStrikeTick;
    }

    /// @notice This struct represents each individual vault as a whole
    /// @param active Whether or not the vault is active
    /// @param openedAt Unix timestamp of when the vault was opened
    /// @param expiresAt The length of the vault - UNIX timestamp
    /// @param ltv The loan-to-value ratio of the vault, expressed as bps of the collateral value
    /// @param collateralAsset The address of the collateral asset (ERC20)
    /// @param cashAsset The address of the cash asset (ERC20)
    /// @param collateralAmount The amount of the collateral asset to be deposited when opening the vault
    /// @param cashAmount The amount of the cash asset received after swapping from collateral
    /// @param liquidityPool The address of the liquidity pool where cash is locked
    /// @param lockedPoolCash The amount of cash that is currently locked in the liquidity pool for this particular vault
    /// @param startingPrice The price of the cash asset in terms of 1e18 of the collateral asset at the time of opening the vault
    /// @param putStrikePrice The strike price of the put option in terms of 1e18 of the collateral asset
    /// @param callStrikePrice The strike price of the call option in terms of 1e18 of the collateral asset
    /// @param putStrikeTick The tick at which the put option is struck
    /// @param callStrikeTick The tick at which the call option is struck
    /// @param loanBalance amount of cash that is currently unlocked (withdrawable); this is the only state var that changes during a vault's lifetime
    /// @param lockedVaultCash The amount of cash that is currently locked (unwithdrawable)
    struct Vault {
        /* ----- Basic Vault Info ----- */
        bool active;
        uint32 openedAt;
        uint32 expiresAt;
        uint32 duration;
        uint256 ltv;
        /* ---- Asset Specific Info ----- */
        address collateralAsset;
        address cashAsset;
        uint256 collateralAmount;
        uint256 cashAmount;
        /* ----- Liquidity Pool Stuff ----- */
        address liquidityPool;
        uint256 lockedPoolCash;
        uint256 initialCollateralPrice;
        uint256 putStrikePrice;
        uint256 callStrikePrice;
        uint24 putStrikeTick;
        uint24 callStrikeTick;
        /* ----- Vault Specific Stuff ----- */
        uint256 loanBalance;
        uint256 lockedVaultCash;
    }
}
