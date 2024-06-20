// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockUniRouter } from "../utils/MockUniRouter.sol";
import { MockEngine } from "../../test/utils/MockEngine.sol";
import { CollarPool } from "../../src/implementations/CollarPool.sol";
import { CollarVaultManager } from "../../src/implementations/CollarVaultManager.sol";
import { CollarEngine } from "../../src/implementations/CollarEngine.sol";
import { ERC6909TokenSupply } from "@erc6909/ERC6909TokenSupply.sol";
import { ICollarVaultState } from "../../src/interfaces/ICollarVaultState.sol";

contract CollarPoolConstraintsTest is Test {
    TestERC20 cashAsset;
    TestERC20 collateralAsset;
    MockUniRouter router;
    MockEngine engine;
    CollarPool pool;
    CollarVaultManager manager;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address user4 = makeAddr("user4");
    address user5 = makeAddr("user5");
    address user6 = makeAddr("user6");

    function setUp() public {
        cashAsset = new TestERC20("Test1", "TST1");
        collateralAsset = new TestERC20("Test2", "TST2");

        router = new MockUniRouter();
        engine = new MockEngine(address(router));

        cashAsset.mint(address(router), 100_000 ether);
        collateralAsset.mint(address(router), 100_000 ether);

        manager = new CollarVaultManager(address(engine), user1);

        engine.forceRegisterVaultManager(user1, address(manager));
        engine.addLTV(9000);

        engine.addSupportedCashAsset(address(cashAsset));
        engine.addSupportedCollateralAsset(address(collateralAsset));

        engine.addCollarDuration(100);

        pool = new CollarPool(address(engine), 100, address(cashAsset), address(collateralAsset), 100, 9000);

        engine.addLiquidityPool(address(pool));

        vm.label(address(cashAsset), "Test Token 1 // Pool Cash Token");
        vm.label(address(collateralAsset), "Test Token 2 // Collateral");

        vm.label(address(pool), "CollarPool");
        vm.label(address(engine), "CollarEngine");

        mintTokensAndApprovePool(user1);
        mintTokensAndApprovePool(address(manager));
    }

    function mintTokensAndApprovePool(address recipient) public {
        startHoax(recipient);
        cashAsset.mint(recipient, 100_000 ether);
        collateralAsset.mint(recipient, 100_000 ether);
        cashAsset.approve(address(pool), 100_000 ether);
        collateralAsset.approve(address(pool), 100_000 ether);
        vm.stopPrank();
    }

    function mintTokensToUserAndApprovePool(address user) public {
        startHoax(user);
        cashAsset.mint(user, 100_000 ether);
        collateralAsset.mint(user, 100_000 ether);
        cashAsset.approve(address(pool), 100_000 ether);
        collateralAsset.approve(address(pool), 100_000 ether);
        vm.stopPrank();
    }

    function mintTokensToUserAndApproveManager(address user) public {
        startHoax(user);
        cashAsset.mint(user, 100_000 ether);
        collateralAsset.mint(user, 100_000 ether);
        cashAsset.approve(address(manager), 100_000 ether);
        collateralAsset.approve(address(manager), 100_000 ether);
        vm.stopPrank();
    }

    function test_addLiquidity() public {
        startHoax(user1);

        uint freeLiquidityStart = pool.freeLiquidity();
        uint lockedLiquidityStart = pool.lockedLiquidity();
        uint totalLiquidityStart = pool.totalLiquidity();

        assertEq(totalLiquidityStart, freeLiquidityStart + lockedLiquidityStart);

        pool.addLiquidityToSlot(115, 100e18);

        assertEq(pool.totalLiquidity(), totalLiquidityStart + 100e18);
        assertEq(pool.lockedLiquidity(), lockedLiquidityStart);
        assertEq(pool.freeLiquidity(), freeLiquidityStart + 100e18);
    }

    function test_withdrawLiquidity() public {
        startHoax(user1);

        uint freeLiquidityStart = pool.freeLiquidity();
        uint lockedLiquidityStart = pool.lockedLiquidity();
        uint totalLiquidityStart = pool.totalLiquidity();

        assertEq(totalLiquidityStart, freeLiquidityStart + lockedLiquidityStart);

        pool.addLiquidityToSlot(125, 100e18);

        assertEq(pool.totalLiquidity(), totalLiquidityStart + 100e18);

        pool.withdrawLiquidityFromSlot(125, 50e18);

        assertEq(pool.totalLiquidity(), totalLiquidityStart + 50e18);
        assertEq(pool.freeLiquidity(), freeLiquidityStart + 50e18);
        assertEq(pool.lockedLiquidity(), lockedLiquidityStart);
    }

    function test_mintPoolPositionTokens() public {
        startHoax(user1);

        uint freeLiquidityStart = pool.freeLiquidity();
        uint lockedLiquidityStart = pool.lockedLiquidity();
        uint totalLiquidityStart = pool.totalLiquidity();

        assertEq(totalLiquidityStart, freeLiquidityStart + lockedLiquidityStart);

        pool.addLiquidityToSlot(130, 100e18);

        assertEq(pool.totalLiquidity(), totalLiquidityStart + 100e18);
        assertEq(pool.freeLiquidity(), freeLiquidityStart + 100e18);
        assertEq(pool.lockedLiquidity(), lockedLiquidityStart);

        bytes32 uuid = keccak256("test_uuid");

        startHoax(address(manager));
        pool.openPosition(uuid, 130, 1e18, block.timestamp + 100);

        assertEq(pool.totalLiquidity(), totalLiquidityStart + 100e18);
        assertEq(pool.freeLiquidity(), freeLiquidityStart + 99e18);
        assertEq(pool.lockedLiquidity(), lockedLiquidityStart + 1e18);
    }

    function test_redeemPoolPositionTokens() public {
        mintTokensToUserAndApproveManager(user1);
        mintTokensToUserAndApprovePool(user2);

        startHoax(user2);

        uint freeLiquidityStart = pool.freeLiquidity();
        uint lockedLiquidityStart = pool.lockedLiquidity();
        uint totalLiquidityStart = pool.totalLiquidity();
        uint redeemLiquidityStart = pool.redeemableLiquidity();

        pool.addLiquidityToSlot(110, 25_000);

        ICollarVaultState.AssetSpecifiers memory assets = ICollarVaultState.AssetSpecifiers({
            collateralAsset: address(collateralAsset),
            collateralAmount: 100,
            cashAsset: address(cashAsset),
            cashAmount: 100
        });

        ICollarVaultState.CollarOpts memory collarOpts =
            ICollarVaultState.CollarOpts({ duration: 100, ltv: 9000 });

        ICollarVaultState.LiquidityOpts memory liquidityOpts = ICollarVaultState.LiquidityOpts({
            liquidityPool: address(pool),
            putStrikeTick: 90,
            callStrikeTick: 110
        });

        engine.setCurrentAssetPrice(address(collateralAsset), 1e18);

        startHoax(user1);
        bytes32 uuid = manager.openVault(assets, collarOpts, liquidityOpts, false);

        ICollarVaultState.Vault memory vault = manager.vaultInfo(uuid);

        assertEq(vault.lockedVaultCash, 10);
        assertEq(vault.lockedPoolCash, 10);

        skip(100);

        engine.setHistoricalAssetPrice(address(collateralAsset), vault.expiresAt, 0.5e18);

        startHoax(user2);

        manager.closeVault(uuid);

        ERC6909TokenSupply poolTokens = ERC6909TokenSupply(address(pool));

        uint userPoolTokenBalance = poolTokens.balanceOf(user2, uint(uuid));

        assertEq(userPoolTokenBalance, 10);

        vm.roll(100);

        CollarPool(pool).redeem(uuid, 10);

        assertEq(pool.totalLiquidity(), totalLiquidityStart + 24_990);
        assertEq(pool.freeLiquidity(), freeLiquidityStart + 24_990);
        assertEq(pool.lockedLiquidity(), lockedLiquidityStart);
        assertEq(pool.redeemableLiquidity(), redeemLiquidityStart);

        //assertEq(pool.totalLiquidity(),);
        //assertEq(pool.freeLiquidity(),);
        //assertEq(pool.lockedLiquidity(),);
    }
    /*
    function test_redeemCollateralUpBeyondStrike() public {
        startHoax(user1);

        uint256 freeLiquidityStart = pool.freeLiquidity();
        uint256 lockedLiquidityStart = pool.lockedLiquidity();
        uint256 totalLiquidityStart = pool.totalLiquidity();

        assertEq(totalLiquidityStart, freeLiquidityStart + lockedLiquidityStart);
    }

    function test_redeemCollateralDownBeyondStrike() public {
        startHoax(user1);

        uint256 freeLiquidityStart = pool.freeLiquidity();
        uint256 lockedLiquidityStart = pool.lockedLiquidity();
        uint256 totalLiquidityStart = pool.totalLiquidity();

        assertEq(totalLiquidityStart, freeLiquidityStart + lockedLiquidityStart);
    }

    function test_redeemCollateralDownSomewhat() public {
        startHoax(user1);

        uint256 freeLiquidityStart = pool.freeLiquidity();
        uint256 lockedLiquidityStart = pool.lockedLiquidity();
        uint256 totalLiquidityStart = pool.totalLiquidity();

        assertEq(totalLiquidityStart, freeLiquidityStart + lockedLiquidityStart);
    }

    function test_redeemCollateralUpSomewhat() public {
        startHoax(user1);

        uint256 freeLiquidityStart = pool.freeLiquidity();
        uint256 lockedLiquidityStart = pool.lockedLiquidity();
        uint256 totalLiquidityStart = pool.totalLiquidity();

        assertEq(totalLiquidityStart, freeLiquidityStart + lockedLiquidityStart);
    }
    */
}
