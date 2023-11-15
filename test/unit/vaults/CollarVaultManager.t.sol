// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import { TestERC20 } from "../../utils/TestERC20.sol";
import { CollarVaultState, CollarVaultConstants } from "../../../src/vaults/interfaces/CollarLibs.sol";
import { CollarVaultManager } from "../../../src/vaults/implementations/CollarVaultManager.sol";
import { CollarLiquidityPool } from "../../../src/liquidity/implementations/CollarLiquidityPool.sol";

contract CollarVaultManagerTest is Test {
    TestERC20 collateral;
    TestERC20 cash;
    CollarVaultManager manager;
    CollarLiquiditiyPool pool;

    function setUp() public {
        collateral = new TestERC20("Collateral", "CLT");
        cash = new TestERC20("Cash", "CSH");
        manager = new CollarVaultManager();
        pool = new CollarLiquidityPool(address(cash));
    }

    function test_createVault() public {
        CollarVaultState.AssetSpecifiers memory assetOpts = CollarVaultState.AssetSpecifiers(
            address(collateral),
            1000e18,
            address(cash),
            1000e18
        );

        CollarVaultState.CollarOpts memory collarOpts = CollarVaultState.CollarOpts(
            90,
            110,
            block.timestamp + 90 days,
            90
        );

        uint24[] memory ticks = new uint24[](2);

        ticks[0] = 100;
        ticks[1] = 110;

        uint256[] memory amounts = new uint256[](2);

        amounts[0] = 1000e18;
        amounts[1] = 1000e18;

        CollarVaultState.LiquidityOpts memory liquidityOpts = CollarVaultState.LiquidityOpts(
            address(pool),
            ticks,
            amounts
        );

        bytes32 uuid = manager.openVault(
            assetOpts,
            collarOpts,
            liquidityOpts
        );
    }
}