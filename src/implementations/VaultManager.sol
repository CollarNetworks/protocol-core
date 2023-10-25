// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarVaultManager } from "../interfaces/IVaultManager.sol";

contract CollarVaultManager is ICollarVaultManager {
    modifier vaultExists(bytes32 vaultUUID) {
        if (vaultIndexByUUID[vaultUUID] == 0) revert NonExistentVault(vaultUUID);
        _;
    }

    constructor(address owner) {
        user = owner;
    }

    function isActive(bytes32 vaultUUID) public override view
    vaultExists(vaultUUID) returns (bool) {
        return vaultsByUUID[vaultUUID].active;
    }

    function isExpired(bytes32 vaultUUID) public override view
    vaultExists(vaultUUID) returns (bool) {
        return vaultsByUUID[vaultUUID].collarOpts.expiry > block.timestamp;
    }

    function getExpiry(bytes32 vaultUUID) public override view
    vaultExists(vaultUUID) returns (uint256) {
        return vaultsByUUID[vaultUUID].collarOpts.expiry;
    }

    function timeRemaining(bytes32 vaultUUID) public override view
    vaultExists(vaultUUID) returns (uint256) {
        uint256 expiry = getExpiry(vaultUUID);

        if (expiry < block.timestamp) return 0;

        return expiry - block.timestamp;
    }

    function depositCash(bytes32 vaultUUID, uint256 amount, address from) external override
    vaultExists(vaultUUID) returns (uint256) {
        revert("Not implemented");
    }

    function withrawCash(bytes32 vaultUUID, uint256 amount, address to) external override
    vaultExists(vaultUUID) returns (uint256) {
        revert("Not implemented");
    }

    function openVault(
        AssetSpecifiers calldata assetSpecifiers,
        CollarOpts calldata collarOpts,
        LiquidityOpts calldata liquidityOpts
    ) external override returns (bytes32) {
        // verify asset specifiers

        // very collar opts

        // very liquidity opts

        // tranfer collateral

        // swap, if necessary

        // lock liquidity

        // set storage struct

        revert("Not implemented");
    }

    function finalizeVault(
        bytes32 vaultUUID
    ) external override
    vaultExists(vaultUUID) returns (int256) {
        // retrieve final price values

        // calculate payouts

        // unlock liquidity

        // swap, if necessary

        // transfer user payout to this contract, if any

        // mark vault as finalized

        // set storage struct

        revert("Not implemented");
    }
}