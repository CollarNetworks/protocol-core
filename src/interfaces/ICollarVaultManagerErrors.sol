// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarCommonErrors } from "./ICollarCommonErrors.sol";

interface ICollarVaultManagerErrors is ICollarCommonErrors {
    /// @notice Indicates that, upon attempting to open a vault, a trade was not able to be executed
    error TradeNotViable();

    /// @notice Indicates that the supplied liquidity pool is not valid per the Engine
    error InvalidPool();

    /// @notice Indicates that the vault specified does not exist
    error NonExistentVault();

    /// @notice Indicates that the vault is inactive
    error InactiveVault();

    /// @notice Indicates that the LTV parameter provided is not valid per the Engine
    error InvalidLTV();

    /// @notice Indicates that someone other than the authorized user has attempted access
    error OnlyUser();

}

/*

/// @notice Errors for the vault manager
library CollarVaultManagerErrors {
    



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

*/