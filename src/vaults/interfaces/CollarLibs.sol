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

    /// @notice Indicates that the caller is not the owner of the contract, but should be
    error NotOwner(address who);

    /// @notice Indicates that the ltv provided on vault open is not valid
    error InvalidLTV(uint256 providedLTV);

    /// @notice Indicates that the provided call and strike parameters on vault open are not valid
    error InvalidStrikeOpts(uint256 callStrike, uint256 putStrike);

    /// @notice Indicates that the provided call strike prarameter is not valid
    error InvalidCallStrike(uint256 callStrike);

    /// @notice Indicates that the provided put strike parameter is not valid
    error InvalidPutStrike(uint256 putStrike);

    /// @notice Indicates that there is not sufficient unlocked liquidity to open a vault with the provided parameters
    error InsufficientLiquidity(uint24 tick, uint256 amount, uint256 available);

    /// @notice Indicates that the ltv would be too low if the action were to be executed
    error ExceedsMinLTV(uint256 ltv, uint256 minLTV);
}

/// @notice Data structures for the vault manager
library CollarVaultState {
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
        uint24[] ticks;
        uint256[] amounts;
    }

    /// @notice This struct represents each individual vault as a whole
    /// @dev We use a mapping below to store each vault by unique identifier (UUID)
    /// @param collateralAmountInitial The amount of collateral deposited into the vault at the time of creation
    /// @param collateralPriceInitial The price of the collateral asset at the time of creation
    /// @param withdrawn The amount of cash withdrawn as a loan
    /// @param maxWithdrawable The maximum amount of cash withdrawable as a loan
    /// @param nonWithdrawable The amount of cash that is not withdrawable as part of the loan
    /// @param active Whether or not the vault is active (if true, it has not been finalized)
    /// @param assetSpecifiers The asset specifiers for the vault
    /// @param collarOpts The collar options for the vault
    /// @param liquidityOpts The liquidity options for the vault
    struct Vault {
        uint256 collateralAmountInitial;
        uint256 collateralPriceInitial;
        uint256 collateralValueInitial;

        uint256 withdrawn;
        uint256 maxWithdrawable;
        uint256 nonWithdrawable;

        bool active;

        AssetSpecifiers assetSpecifiers;
        CollarOpts collarOpts;
        LiquidityOpts liquidityOpts;
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