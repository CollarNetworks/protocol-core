// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarVaultLens } from "../interfaces/ICollarVaultLens.sol";
import { ICollarVaultManager } from "../interfaces/ICollarVaultManager.sol";
import { CollarVaultManagerErrors, CollarVaultState } from "../interfaces/CollarLibs.sol";

abstract contract CollarVaultLens is ICollarVaultLens, ICollarVaultManager {
    modifier vaultExists(bytes32 vaultUUID) {
        if (vaultIndexByUUID[vaultUUID] == 0) revert CollarVaultManagerErrors.NonExistentVault(vaultUUID);
        _;
    }

    modifier vaultIsActive(bytes32 vaultUUID) {
        if (!isActive(vaultUUID)) revert CollarVaultManagerErrors.InactiveVault(vaultUUID);
        _;
    }

    modifier vaultIsExpired(bytes32 vaultUUID) {
        if (!isExpired(vaultUUID)) revert CollarVaultManagerErrors.NotYetExpired(vaultUUID);
        _;
    }

    function getVault(bytes32 vaultUUID) public view returns (CollarVaultState.Vault memory) {
        return vaultsByUUID[vaultUUID];
    }

    function isActive(
        bytes32 vaultUUID
    ) public override view vaultExists(vaultUUID) returns (bool) {
        return vaultsByUUID[vaultUUID].active;
    }

    function isExpired(
        bytes32 vaultUUID
    ) public override view vaultExists(vaultUUID) returns (bool) {
        return vaultsByUUID[vaultUUID].expiresAt > block.timestamp;
    }

    function getExpiry(
        bytes32 vaultUUID
    ) public override view vaultExists(vaultUUID) returns (uint256) {
        return vaultsByUUID[vaultUUID].expiresAt;
    }

    function timeRemaining(
        bytes32 vaultUUID
    ) public override view vaultExists(vaultUUID) returns (uint256) {
        uint256 expiresAt = getExpiry(vaultUUID);

        if (expiresAt < block.timestamp) return 0;

        return expiresAt - block.timestamp;
    } 
}