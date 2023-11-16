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

    function isActive(
        bytes32 vaultUUID
    ) public override view vaultExists(vaultUUID) returns (bool) {
        return vaultsByUUID[vaultUUID].active;
    }

    function isExpired(
        bytes32 vaultUUID
    ) public override view vaultExists(vaultUUID) returns (bool) {
        return vaultsByUUID[vaultUUID].expiry > block.timestamp;
    }

    function getExpiry(
        bytes32 vaultUUID
    ) public override view vaultExists(vaultUUID) returns (uint256) {
        return vaultsByUUID[vaultUUID].expiry;
    }

    function timeRemaining(
        bytes32 vaultUUID
    ) public override view vaultExists(vaultUUID) returns (uint256) {
        uint256 expiry = getExpiry(vaultUUID);

        if (expiry < block.timestamp) return 0;

        return expiry - block.timestamp;
    } 
}