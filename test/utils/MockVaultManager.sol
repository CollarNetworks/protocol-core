// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { CollarVaultState } from "../../src/libs/CollarLibs.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ICollarVaultManager } from "../../src/interfaces/ICollarVaultManager.sol";

contract MockVaultManager is ICollarVaultManager {

    constructor(address _engine, address _owner) ICollarVaultManager(_engine, _owner) { }

    function openVault(
        CollarVaultState.AssetSpecifiers calldata /* assetOpts */,
        CollarVaultState.CollarOpts calldata /* collarOpts */,
        CollarVaultState.LiquidityOpts calldata  /* liquidityOpts */
    ) external override returns (bytes32 uuid) { }

    function closeVault(bytes32 /* uuid */) external override { }

    function redeem(bytes32 /* uuid */, uint256 /* amount */) external override { }

    function previewRedeem(bytes32 /* uuid */, uint256 /* amount */) external override returns (uint256) {return 0;}

    function withdraw(bytes32 /* uuid */, uint256 /* amount */) external override { }

    function vaultInfo(bytes32 /* uuid */) external override view returns (bytes memory data) {
        data = bytes("a;lsdkfj");
     }
}