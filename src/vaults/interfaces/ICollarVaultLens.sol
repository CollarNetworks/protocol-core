// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

/// @notice View functions for vaults
abstract contract ICollarVaultLens {
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

    /// @notice Returns the bps of the LTV ratio of the vault
    /// @param vaultUUID The UUID of the vault to check
    function getLTV(bytes32 vaultUUID) public virtual view returns (uint256);
}