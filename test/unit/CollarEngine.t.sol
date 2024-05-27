// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockUniRouter } from "../utils/MockUniRouter.sol";
import { CollarVaultManager } from "../../src/implementations/CollarVaultManager.sol";
import { CollarEngine } from "../../src/implementations/CollarEngine.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ICollarEngineErrors } from "../../src/interfaces/ICollarEngine.sol";
import { CollarPool } from "../../src/implementations/CollarPool.sol";

contract CollarEngineTest is Test, ICollarEngineErrors {
    TestERC20 token1;
    TestERC20 token2;
    MockUniRouter router;
    CollarVaultManager manager;
    CollarEngine engine;
    address pool1;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    // below we copy error messages from contracts since they aren't by default "public" or otherwise accessible

    error OwnableUnauthorizedAccount(address account);

    bytes user1NotAuthorized = abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(user1));

    function setUp() public {
        token1 = new TestERC20("Test1", "TST1");
        token2 = new TestERC20("Test2", "TST2");
        router = new MockUniRouter();

        engine = new CollarEngine(address(router));
        manager = CollarVaultManager(engine.createVaultManager());

        engine.addLTV(9000);

        pool1 = address(new CollarPool(address(engine), 1, address(token1), address(token2), 100, 9000));
    }

    function mintTokensAndApprovePool(address recipient) public {
        startHoax(recipient);
        token1.mint(recipient, 100_000);
        token2.mint(recipient, 100_000);
        token1.approve(address(pool1), 100_000);
        token2.approve(address(pool1), 100_000);
        vm.stopPrank();
    }

    function test_deploymentAndDeployParams() public view {
        assertEq(address(engine.dexRouter()), address(router));
        assertEq(engine.owner(), address(this));
    }

    function test_addLiquidityPool() public {
        assertFalse(engine.isSupportedLiquidityPool(address(pool1)));
        engine.addLiquidityPool(address(pool1));
        assertTrue(engine.isSupportedLiquidityPool(address(pool1)));
    }

    function test_supportedLiquidityPoolsLength() public {
        engine.addLiquidityPool(address(pool1));
        assertEq(engine.supportedLiquidityPoolsLength(), 1);
        engine.removeLiquidityPool(address(pool1));
        assertEq(engine.supportedLiquidityPoolsLength(), 0);
    }

    function test_removeLiquidityPool() public {
        engine.addLiquidityPool(address(pool1));
        engine.removeLiquidityPool(address(pool1));
        assertFalse(engine.isSupportedLiquidityPool(address(pool1)));
    }

    function test_addLiquidityPool_NoAuth() public {
        startHoax(user1);

        vm.expectRevert(user1NotAuthorized);
        engine.addLiquidityPool(address(pool1));

        vm.stopPrank();
    }

    function test_removeLiquidityPool_NoAuth() public {
        startHoax(user1);

        vm.expectRevert(user1NotAuthorized);
        engine.removeLiquidityPool(address(pool1));

        vm.stopPrank();
    }

    function test_addSupportedCashAsset() public {
        assertFalse(engine.isSupportedCashAsset(address(token1)));
        engine.addSupportedCashAsset(address(token1));
        assertTrue(engine.isSupportedCashAsset(address(token1)));
    }

    function test_addSupportedCashAsset_NoAuth() public {
        startHoax(user1);
        vm.expectRevert(user1NotAuthorized);
        engine.addSupportedCashAsset(address(token1));
        vm.stopPrank();
    }

    function test_addSupportedCashAsset_Duplicate() public {
        engine.addSupportedCashAsset(address(token1));
        vm.expectRevert(abi.encodeWithSelector(CashAssetAlreadySupported.selector, address(token1)));
        engine.addSupportedCashAsset(address(token1));
    }

    function test_removeSupportedCashAsset() public {
        engine.addSupportedCashAsset(address(token1));
        engine.removeSupportedCashAsset(address(token1));
        assertFalse(engine.isSupportedCashAsset(address(token1)));
    }

    function test_removeSupportedCashAsset_NoAuth() public {
        startHoax(user1);
        vm.expectRevert(user1NotAuthorized);
        engine.removeSupportedCashAsset(address(token1));
        vm.stopPrank();
    }

    function test_removeSupportedCashAsset_NonExistent() public {
        vm.expectRevert(abi.encodeWithSelector(CashAssetNotSupported.selector, address(token1)));
        engine.removeSupportedCashAsset(address(token1));

        vm.expectRevert(abi.encodeWithSelector(CollateralAssetNotSupported.selector, address(token2)));
        engine.removeSupportedCollateralAsset(address(token2));
    }

    function test_addSupportedCollateralAsset() public {
        assertFalse(engine.isSupportedCollateralAsset(address(token1)));
        engine.addSupportedCollateralAsset(address(token1));
        assertTrue(engine.isSupportedCollateralAsset(address(token1)));
    }

    function test_addSupportedCollateralAsset_NoAuth() public {
        startHoax(user1);
        vm.expectRevert(user1NotAuthorized);
        engine.addSupportedCollateralAsset(address(token1));
        vm.stopPrank();
    }

    function test_addSupportedCollateralAsset_Duplicate() public {
        engine.addSupportedCollateralAsset(address(token1));
        vm.expectRevert(abi.encodeWithSelector(CollateralAssetAlreadySupported.selector, address(token1)));
        engine.addSupportedCollateralAsset(address(token1));
    }

    function test_removeSupportedCollateralAsset() public {
        engine.addSupportedCollateralAsset(address(token1));
        engine.removeSupportedCollateralAsset(address(token1));
        assertFalse(engine.isSupportedCollateralAsset(address(token1)));
    }

    function test_removeSupportedCollateralAsset_NoAuth() public {
        startHoax(user1);
        vm.expectRevert(user1NotAuthorized);
        engine.removeSupportedCollateralAsset(address(token1));
        vm.stopPrank();
    }

    function test_addCollarDuration() public {
        assertFalse(engine.isValidCollarDuration(1));
        engine.addCollarDuration(1);
        assertTrue(engine.isValidCollarDuration(1));
    }

    function test_addCollarDuration_NoAuth() public {
        startHoax(user1);
        vm.expectRevert(user1NotAuthorized);
        engine.addCollarDuration(1);
        vm.stopPrank();
    }

    function test_removeCollarDuration() public {
        engine.addCollarDuration(1);
        engine.removeCollarDuration(1);
        assertFalse(engine.isValidCollarDuration(1));
    }

    function test_removeCollarDuration_NoAuth() public {
        startHoax(user1);
        vm.expectRevert(user1NotAuthorized);
        engine.removeCollarDuration(1);
        vm.stopPrank();
    }

    function test_getCurrentAssetPrice_InvalidAsset() public {
        vm.expectRevert();
        engine.getCurrentAssetPrice(address(token1), address(token2));
    }

    function test_createVaultManager() public {
        startHoax(user1);

        address createdVaultManager = engine.createVaultManager();
        address storedVaultManager = engine.addressToVaultManager(user1);

        assertEq(createdVaultManager, storedVaultManager);

        address vaultManager = createdVaultManager;

        address vaultManagerOwner = CollarVaultManager(vaultManager).owner();
        address vaultManagerUSer = CollarVaultManager(vaultManager).user();
        address vaultManagerEngine = CollarVaultManager(vaultManager).engine();

        assertEq(vaultManagerOwner, user1);
        assertEq(vaultManagerUSer, user1);
        assertEq(vaultManagerEngine, address(engine));

        vm.stopPrank();
    }

    function test_createVaultManager_Duplicate() public {
        startHoax(user1);

        address vaultManager = engine.createVaultManager();

        vm.expectRevert(abi.encodeWithSelector(VaultManagerAlreadyExists.selector, user1, address(vaultManager)));
        engine.createVaultManager();

        vm.stopPrank();
    }

    function test_removeLTV() public {
        engine.removeLTV(9000);
        assertFalse(engine.isValidLTV(9000));
    }

    function test_vaultManagersLength() public {
        vm.startPrank(user1);
        engine.createVaultManager();
        vm.stopPrank();
        vm.startPrank(user2);
        engine.createVaultManager();
        vm.stopPrank();
        assertEq(engine.vaultManagersLength(), 3);
    }

    function test_getVaultManager() public {
        vm.startPrank(user1);
        uint256 vaultManagerCount = engine.vaultManagersLength();
        engine.createVaultManager();
        address vaultManager = engine.getVaultManager(vaultManagerCount);

        assertEq(vaultManager, engine.addressToVaultManager(user1));
        vm.stopPrank();
    }

    function testFail_getVaultManager() public view {
        address vaultManager = engine.getVaultManager(1);
    }

    function test_supportedCashAssetsLength() public {
        engine.addSupportedCashAsset(address(token1));
        assertEq(engine.supportedCashAssetsLength(), 1);
        engine.removeSupportedCashAsset(address(token1));
        assertEq(engine.supportedCashAssetsLength(), 0);
    }

    function test_getSupportedCashAsset() public {
        engine.addSupportedCashAsset(address(token1));
        assertEq(engine.getSupportedCashAsset(0), address(token1));
    }

    function test_supportedCollateralAssetsLength() public {
        engine.addSupportedCollateralAsset(address(token1));
        assertEq(engine.supportedCollateralAssetsLength(), 1);
        engine.removeSupportedCollateralAsset(address(token1));
        assertEq(engine.supportedCollateralAssetsLength(), 0);
    }

    function test_getSupportedCollateralAsset() public {
        engine.addSupportedCollateralAsset(address(token1));
        assertEq(engine.getSupportedCollateralAsset(0), address(token1));
    }

    function test_getSupportedLiquidityPool() public {
        engine.addLiquidityPool(address(pool1));
        assertEq(engine.getSupportedLiquidityPool(0), address(pool1));
    }

    function test_validCollarDurationsLength() public {
        engine.addCollarDuration(1);
        assertEq(engine.validCollarDurationsLength(), 1);
        engine.removeCollarDuration(1);
        assertEq(engine.validCollarDurationsLength(), 0);
    }

    function test_getValidCollarDuration() public {
        engine.addCollarDuration(1);
        assertEq(engine.getValidCollarDuration(0), 1);
    }

    function test_validLTVsLength() public {
        engine.addLTV(8000);
        assertEq(engine.validLTVsLength(), 2);
        engine.removeLTV(8000);
        assertEq(engine.validLTVsLength(), 1);
    }

    function test_getValidLTV() public {
        engine.addLTV(8000);
        assertEq(engine.getValidLTV(1), 8000);
    }
}
