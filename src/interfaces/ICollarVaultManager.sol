// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarVaultManagerEvents } from "./events/ICollarVaultManagerEvents.sol";
import { ICollarVaultManagerErrors } from "./errors/ICollarVaultManagerErrors.sol";
import { ICollarVaultState } from "./ICollarVaultState.sol";
import { ERC6909TokenSupply } from "@erc6909/ERC6909TokenSupply.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

abstract contract ICollarVaultManager is
    ICollarVaultState,
    ICollarVaultManagerErrors,
    ICollarVaultManagerEvents,
    ERC6909TokenSupply,
    Ownable
{
    // ----- IMMUTABLES ----- //

    address public immutable user;
    address public immutable engine;

    // ----- SO THAT THE ABI PICKS UP THE VAULT STRUCT ----- //
    event VaultForABI(Vault vault);

    // ----- STATE VARIABLES ----- //

    uint256 public vaultCount;

    mapping(bytes32 uuid => Vault vault) internal vaultsByUUID;
    mapping(uint256 vaultNonce => bytes32 UUID) public vaultsByNonce;
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

    /// @notice Get the n-th vault state
    /// @param vaultNonce Nonce of the vault to get state for
    function vaultInfoByNonce(uint256 vaultNonce) external view virtual returns (bytes calldata data);

    /// @notice Get the UUID of a vault by its nonce
    /// @param vaultNonce Nonce of the vault to get the UUID for
    function getVaultUUID(uint256 vaultNonce) external view virtual returns (bytes32 uuid);

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
        // addresses & amounts of collateral & cash assets
        AssetSpecifiers calldata assets,
        // expiry & ltv
        CollarOpts calldata collarOpts,
        // pool address, callstrike & amount to lock there, putstrike
        LiquidityOpts calldata liquidityOpts,
        bool withdrawLoan
    ) public virtual returns (bytes32 uuid);

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
    function withdraw(bytes32 uuid, uint256 amount) public virtual;
}
