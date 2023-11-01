// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { ICollarVaultManager } from "../../src/interfaces/IVaultManager.sol";
import { CollarVaultManager } from "../../src/implementations/VaultManager.sol";

contract VaultManagerTest is Test {
    address user1 = makeAddr("user1");

    CollarVaultManager vaultManager;

    function setUp() public {
        vaultManager = new CollarVaultManager(user1);    
    }

    function test_openVault() public {
        ICollarVaultManager.AssetSpecifiers memory assetSpecifiers;
        ICollarVaultManager.CollarOpts memory collarOpts;
        ICollarVaultManager.LiquidityOpts memory liquidityOpts;
    }

    function test_closeVault() public {

    }
}