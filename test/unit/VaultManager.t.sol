// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { ICollarVaultManager } from "../../src/interfaces/IVaultManager.sol";
import { CollarVaultManager } from "../../src/implementations/VaultManager.sol";
import { TestERC20 } from "../utils/TestERC20.sol";

contract VaultManagerTest is Test {
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");

    TestERC20 token1;
    TestERC20 token2;
    TestERC02 token3;

    CollarVaultManager vaultManager;

    function setUp() public {
        // deploy test tokens and vault
        vaultManager = new CollarVaultManager(user1);
        token1 = new TestERC20("TestToken1", "TT1");
        token2 = new TestERC20("TestToken2", "TT2");
        token3 = new TestERC20("TestToken3", "TT3");
    }

    function test_openVault() public {
        ICollarVaultManager.AssetSpecifiers memory assetSpecifiers;

        assetSpecifiers.cashAsset = address(token1);
        assetSpecifiers.cashAmount = 100 ether;
        assetSpecifiers.collateralAsset = address(token2);
        assetSpecifiers.collateralAmount = 10 ether;

        ICollarVaultManager.CollarOpts memory collarOpts;

        collarOpts.callStrike = 11_000; // 110%
        collarOpts.putStrike = 9_000;   // 90%
        collarOpts.expiry = block.timestamp + 3 days;
        collarOpts.ltv = 9_000;         // 90%

        ICollarVaultManager.LiquidityOpts memory liquidityOpts;

        // todo: set liquidity opts

    }

    function test_closeVault() public {

    }
}