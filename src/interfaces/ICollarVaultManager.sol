// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { CollarVaultState } from "../libs/CollarLibs.sol";
import { IERC6909WithSupply } from "../interfaces/IERC6909WithSupply.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract ICollarVaultManager is IERC6909WithSupply, Ownable {
    // ----- IMMUTABLES ----- //

    address public immutable user;
    address public immutable engine;

    // ----- STATE VARIABLES ----- //

    uint256 public vaultCount;

    mapping(bytes32 uuid => CollarVaultState.Vault vault) internal vaultsByUUID;
    mapping(bytes32 => uint256) public vaultTokenCashSupply;

    // ----- CONSTRUCTOR ----- //

    constructor(address _engine, address _owner) Ownable(_owner) {
        user = _owner;
        engine = _engine;
        vaultCount = 0;
    }

    // ----- VIEW FUNCTIONS ----- //

    /// @notice Whether or not the vault is expired
    /// @param uuid UUID of the vault to check
    function isVaultExpired(bytes32 uuid) external view virtual returns (bool);

    /// @notice Get the entire vault state as bytes
    /// @param uuid UUID of the vault to get state for
    function vaultInfo(bytes32 uuid) external view virtual returns (bytes calldata data);

    /// @notice Preview the cash amount redeemable for a given amount of tokens for a particular vault
    /// @param uuid UUID of the vault to redeem from
    /// @param amount Amount of tokens to redeem
    function previewRedeem(bytes32 uuid, uint256 amount) external virtual returns (uint256);

    // ----- STATE CHANGING FUNCTIONS ----- //

    /// @notice Opens a new vault
    /// @param assets Data about the assets in the vault & amounts of each
    /// @param collarOpts Data about the collar (expiry & ltv)
    /// @param liquidityOpts Data about the liquidity (pool address, callstrike & amount to lock there, putstrike)
    function openVault(
        CollarVaultState.AssetSpecifiers calldata assets, // addresses & amounts of collateral & cash assets
        CollarVaultState.CollarOpts calldata collarOpts, // expiry & ltv
        CollarVaultState.LiquidityOpts calldata liquidityOpts // pool address, callstrike & amount to lock there, putstrike
    ) external virtual returns (bytes32 uuid);

    /// @notice Closes a vault - expiry must have passed
    /// @param uuid UUID of the vault to close
    function closeVault(bytes32 uuid) external virtual;

    /// @notice Redeems a token for a particular vault - vault must be finalized
    /// @param uuid UUID of the vault to redeem from
    /// @param amount Amount of tokens to redeem
    function redeem(bytes32 uuid, uint256 amount) external virtual;

    /// @notice Withdraws cash from a vault loan
    /// @param uuid UUID of the vault to withdraw from
    /// @param amount Amount of cash to withdraw
    function withdraw(bytes32 uuid, uint256 amount) external virtual;
}
