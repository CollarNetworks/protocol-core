// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { CollarVaultManagerEvents, CollarVaultManagerErrors, CollarVaultState, CollarVaultConstants } from "./CollarLibs.sol";

/// @notice Base contract for the vault manager
abstract contract ICollarVaultManager {
    /// @notice The address of the collar engine, which is what creates the Vault Manager contract per user
    address immutable public engine;

    /// @notice The user that owns the vault
    address user;

    /// @notice The number of vaults a user has opened
    uint256 public vaultCount;

    /// @notice Retrieves the vault details by UUID
    mapping(bytes32 UUID => CollarVaultState.Vault) public vaultsByUUID;

    /// @notice Gives UUID of vault by index (order of creation)
    mapping(uint256 index => bytes32 UUID) public vaultUUIDsByIndex;

    /// @notice Reverse mapping of UUID to index
    mapping(bytes32 UUID => uint256 index) public vaultIndexByUUID;

    /// @notice Count of how many vaults have any particular token as cash
    mapping(address token => uint256 count) public tokenVaultCount;

    /// @notice Total balance of any particular token across all vaults (cash)
    mapping(address token => uint256 totalBalance) public tokenTotalBalance;

    constructor(address _engine) {
        engine = _engine;
    }

    /// @notice Opens a vault with the given asset specifiers and collar options and liquidity sources, if possible
    /// @dev We'll need to make sure the frontend handles all the setup here and passes in correct options
    /// @param assetSpecifiers The asset specifiers for the vault
    /// @param collarOpts The collar options for the vault
    /// @param liquidityOpts The liquidity options for the vault
    /// @return UUID of the vault
    function openVault(
        CollarVaultState.AssetSpecifiers calldata assetSpecifiers,
        CollarVaultState.CollarOpts calldata collarOpts,
        CollarVaultState.LiquidityOpts calldata liquidityOpts
    ) external virtual returns (bytes32 UUID);

    /// @notice Closes a vault and returns the collateral to the user or market maker
    /// @dev This function will revert if the vault is not finalizable
    /// @param vaultUUID The UUID of the vault to close
    function finalizeVault(
        bytes32 vaultUUID
    ) external virtual;

    /// @notice Allows a user to deposit cash (repay their loan) into a particular vault
    /// @param vaultUUID The UUID of the vault to deposit into
    /// @param amount The amount of cash to deposit
    /// @param from The address to send the cash from
    /// @return newUnlockedCashBalance balance of the vault after the deposit
    function depositCash(
        bytes32 vaultUUID, 
        uint256 amount,
        address from
    ) external virtual returns (uint256 newUnlockedCashBalance);
    
    /// @notice Allows a user to withdraw cash (take out a loan) from a particular vault
    /// @param vaultUUID The UUID of the vault to withdraw from
    /// @param amount The amount of cash to withdraw
    /// @param to The address to send the cash to
    /// @return newUnlockedCashBalance balance of the vault after the withdrawal
    function withdrawCash(
        bytes32 vaultUUID, 
        uint256 amount, 
        address to
    ) external virtual returns (uint256 newUnlockedCashBalance);
}