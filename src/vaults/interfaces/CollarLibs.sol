// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

/// @notice Events for the vault manager
library CollarVaultManagerEvents {
    /// @notice Indicates that a vault has been opened
    event VaultOpened(bytes32 vaultId);

    /// @notice Indicates that a vault has been closed
    event VaultClosed(bytes32 vaultId);

    /// @notice Indicates that a loan withdrawal has been made
    event LoanWithdrawal(bytes32 vaultId, uint256 amount);

    /// @notice Indicates that a loan repayment has been made
    event LoanRepayment(bytes32 vaultId, uint256 amount);
}

/// @notice Errors for the vault manager
library CollarVaultManagerErrors {
    /// @notice Indicates that the vault specified does not exist
    error NonExistentVault(bytes32 vaultUUID);

    /// @notice Indicates that the vault is inactive
    error InactiveVault(bytes32 vaultUUID);

    /// @notice Indicates that the vault is active
    error NotYetExpired(bytes32 vaultUUID);

    /// @notice Indicates that the caller is not the owner of the contract, but should be
    error NotOwner(address who);

    /// @notice Indicates that the asset options provided are invalid
    error InvalidAssetSpecifiers();

    /// @notice Indicates that the collar options provided are invalid
    error InvalidCollarOpts();

    /// @notice Indicates that the liquidity options provided are invalid
    error InvalidLiquidityOpts();

    /// @notice Indicates that there is not sufficient unlocked liquidity to open a vault with the provided parameters
    error InsufficientLiquidity(uint24 tick, uint256 amount, uint256 available);

    /// @notice Indicates that the ltv would be too low if the action were to be executed
    error ExceedsMinLTV(uint256 ltv, uint256 minLTV);
}

/// @notice Data structures for the vault manager
library CollarVaultState {
    /// @notice This struct contains information about which assests (and how much of them) are in each vault
    /// @param collateralAsset The address of the collateral asset
    /// @param collateralAmount The minimumamount of the collateral asset
    /// @param cashAsset The address of the cash asset
    /// @param cashAmount The minimum amount of the cash asset to swap the collateral for
    struct AssetSpecifiers {
        address collateralAsset;
        uint256 collateralAmount;
        address cashAsset;
        uint256 cashAmount;
    }

    /// @notice This struct contains information about the collar options for each vault
    /// @param expiry The expiry of the options express as a unix timestamp
    /// @param ltv The maximjum loan-to-value ratio of loans taken out of this vault, expressed as bps of the collateral value
    struct CollarOpts {
        uint256 expiry;
        uint256 ltv;
    }

    /// @notice This struct contains information about how to source the liquidity for each vault
    /// @param liquidityPool The address of the liquidity pool to draw from
    /// @param amount The amount of liquidity locked at the tick
    /// @param tick The tick at which liquidity is locked
    struct LiquidityOpts {
        address liquidityPool;
        uint256 amount;
        uint24 tick;
    }

    /// @notice This struct represents each individual vault as a whole
    /// @param active Whether or not the vault is active
    /// @param openedAt Unix timestamp of when the vault was opened
    /// @param expiresAt The expiry of the vault - UNIX timestamp
    /// @param ltv The loan-to-value ratio of the vault, expressed as bps of the collateral value
    /// @param collateralAsset The address of the collateral asset (ERC20)
    /// @param collateralAmount The amount of the collateral asset to be deposited when opening the vault
    /// @param cashAsset The address of the cash asset (ERC20)
    /// @param cashAmount The amount of the cash asset received after swapping from collateral
    /// @param unlockedCashTotal The amount of cash that is currently unlocked (withdrawable); this is the only state var that changes during a vault's lifetime
    /// @param lockedCashTotal The amount of cash that is currently locked (unwithdrawable)
    /// @param liquidityPool The address of the liquidity pool where cash is locked
    /// @param ticK The tick at which liquidity is locked
    /// @param amount The amount of liquidity locked at the tick
    struct Vault {
        bool active;
        uint256 openedAt;
        uint256 expiresAt;
        uint256 ltv;
        address collateralAsset;
        uint256 collateralAmount;
        address cashAsset;
        uint256 cashAmount;
        uint256 putStrikePrice;
        uint256 callStrikePrice;
        uint256 startingPrice;
        uint256 unlockedCashTotal;
        uint256 lockedCashTotal;
        address liquidityPool;
        uint256 amount;    
        uint24 tick;
    }
}

/// @notice Constants for the vault manager
library CollarVaultConstants {
    /// @notice The maximum global ltv, not changeable; set to 100% for now (in bps)
    uint256 constant public MAX_LTV = 10_000;

    /// @notice The minimum call strike, not changeable; set to 150% for now (in bps)
    uint256 constant public MIN_CALL_STRIKE = 100_000;

    /// @notice The maximum put strike, not changeable; set to 100% for now (in bps)
    uint256 constant public MAX_PUT_STRIKE = 100_000;
}