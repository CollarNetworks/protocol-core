// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { CollarVaultState } from "../libs/CollarLibs.sol";
import { ERC6909 } from "@solmate/tokens/ERC6909.sol";

abstract contract ICollarVaultManager is ERC6909 {
    address immutable user;
    address immutable engine;

    uint256 public vaultCount;

    mapping(uint256 id => uint256) public totalTokenSupply;
    mapping(bytes32 uuid => CollarVaultState.Vault vault) public vaultsByUUID;
    mapping(bytes32 => uint256) public vaultTokenCashSupply;

    constructor(address _engine, address _owner) {
        user = _owner;
        engine = _engine;
        vaultCount = 0;
    }

    function openVault(
        CollarVaultState.AssetSpecifiers calldata assets,       // addresses & amounts of collateral & cash assets
        CollarVaultState.CollarOpts calldata collarOpts,        // expiry & ltv
        CollarVaultState.LiquidityOpts calldata liquidityOpts   // pool address, callstrike & amount to lock there, putstrike
    ) external virtual returns (bytes32 uuid);

    function closeVault(
        bytes32 uuid
    ) external virtual;

    function redeem(
        bytes32 uuid, 
        uint256 amount
    ) external virtual;

    function previewRedeem(
        bytes32 uuid, 
        uint256 amount
    ) external virtual returns (uint256);

    function withdraw(
        bytes32 uuid, 
        uint256 amount
    ) external virtual;
}