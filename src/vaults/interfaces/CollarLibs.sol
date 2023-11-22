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
    /// @param totalLiquidity The total amount of liquidity to draw from the liquidity pool
    /// @param ticks The ticks from which to draw liquidity
    /// @param ratios The ratios of liquidity to draw from in the liquidity pool; must sum to 1e12
    struct LiquidityOpts {
        address liquidityPool;
        uint256 totalLiquidity;
        uint24[] ticks;
        uint256[] ratios;
    }

    /// @notice This struct represents each individual vault as a whole
    /// @param active Whether or not the vault is active
    /// @param expiry The expiry of the vault - UNIX timestamp
    /// @param ltv The loan-to-value ratio of the vault, expressed as bps of the collateral value
    /// @param collateralAsset The address of the collateral asset
    /// @param collateralAmount The amount of the collateral asset
    /// @param cashAsset The address of the cash asset
    /// @param cashAmount The amount of the cash asset
    /// @param unlockedCashTotal The amount of cash that is unlocked (withdrawable) total
    /// @param lockedCashTotal The amount of cash that is locked (unwithdrawable) total
    /// @param liquidityPool The address of the liquidity pool where cash is locked
    /// @param callStrikeTicks The ticks where liquidity is locked, representing potential callstriek payouts
    /// @param tickRatios The ratios of liquidity that are locked in each tick, representing potential callstrike payouts; should sum to 1e12
    /// @param callStrikeAmounts The amounts of liquidity that are locked in each tick< representing potential callstrike payouts
    struct Vault {
        bool active;

        // --- INITIAL VAULT PARAMETERS --- ///

        uint256 expiry;
        uint256 ltv;

        address liquidityPool;

        address cashAsset;
        address collateralAsset;

        // the cash amount is the amount of cash that we swap the collateral for
        uint256 cashAmount;
        uint256 collateralAmount;

        // this specififes the exact call strikes that are to be used
        // but not now much liquidity to use/lock at each callstirke - that comes later
        uint24[] callStrikeTicks;

        // this array of length equal to the above callStrikeTicks array indicates the ratio of lquidity
        // to pull from each tick provided in the above array
        // it must sum to a total of 1e12 or the entire operation should revert
        // these indicate the the ratio at which liquidity is locked at various ticks,
        uint256[] tickRatios;

        // the total locked cash in the vault is the amount that might be forfeit
        // to the market maker in the worst possible case (for the user)
        uint256 lockedVaultCashTotal;

        // the total locked cash in the pool is the amount that might be forfeit
        // to the user in the worse possible case (for the market maker)
        uint256 lockedPoolCashTotal;

        /// --- DYNAMIC VAULT PARAMETERS --- ///

        // the total unlocked cash in the vault is the amount that can be withdrawn by the user
        // this amount will obviously change over time as the vault is withdrawn from by the user
        uint256 unlockedVaultCashTotal;
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