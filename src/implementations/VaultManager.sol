// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarVaultManager } from "../interfaces/IVaultManager.sol";

contract CollarVaultManager is ICollarVaultManager {

    function isActive(bytes32 vaultUUID) external override view returns (bool) {
        revert("Not implemented");
    }

    function isExpired(bytes32 vaultUUID) external override view returns (bool) {
        revert("Not implemented");
    }

    function getExpiry(bytes32 vaultUUID) external override view returns (uint256) {
        revert("Not implemented");
    }

    function timeRemaining(bytes32 vaultUUID) external override view returns (uint256) {
        revert("Not implemented");
    }

    function depositCash(bytes32 vaultUUID, uint256 amount, address from) external override returns (uint256) {
        revert("Not implemented");
    }

    function withrawCash(bytes32 vaultUUID, uint256 amount, address to) external override returns (uint256) {
        revert("Not implemented");
    }

    function openVault(
        AssetSpecifiers calldata assetSpecifiers,
        CollarOpts calldata collarOpts,
        LiquidityOpts calldata liquidityOpts
    ) external override returns (bytes32) {
        revert("Not implemented");
    }

    function finalizeVault(
        bytes32 vaultUUID
    ) external override returns (int256) {
        revert("Not implemented");
    }
}