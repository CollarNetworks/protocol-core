// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockUniRouter } from "../utils/MockUniRouter.sol";
import { MockVaultManager } from "../utils/MockVaultManager.sol";
import { CollarEngine } from "../../src/implementations/CollarEngine.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ICollarEngineErrors } from "../../src/interfaces/ICollarEngine.sol";

contract CollarEngineTest is Test, ICollarEngineErrors {
    TestERC20 token1;
    TestERC20 token2;
    MockUniRouter router;
    MockVaultManager manager;
    CollarEngine engine;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    address pool1 = makeAddr("pool1");

    // below we copy error messages from contracts since they aren't by default "public" or otherwise accessible

    error OwnableUnauthorizedAccount(address account);
    bytes user1NotAuthorized = abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(user1));

    function setUp() public {
        token1 = new TestERC20("Test1", "TST1");
        token2 = new TestERC20("Test2", "TST2");
        router = new MockUniRouter();
        engine = new CollarEngine(address(router));
        manager = new MockVaultManager(address(engine), address(this));
    }

    function test_deploymentAndDeployParams() public {
        assertEq(address(engine.dexRouter()), address(router));
        assertEq(engine.owner(), address(this));
    }

    function test_addRemoveLiquidityPool() public {
        assertFalse(engine.isLiquidityPool(address(pool1)));

        engine.addLiquidityPool(address(pool1));
        assertTrue(engine.isLiquidityPool(address(pool1)));

        engine.removeLiquidityPool(address(pool1));
        assertFalse(engine.isLiquidityPool(address(pool1)));
    }

    function test_addRemoveLiquidityPoolAuth() public {
        startHoax(user1);

        vm.expectRevert(user1NotAuthorized);
        engine.addLiquidityPool(address(pool1));

        vm.expectRevert(user1NotAuthorized);
        engine.removeLiquidityPool(address(pool1));

        vm.stopPrank();
    }

    function test_addRemoveCollateralAssets() public {
        assertFalse(engine.isSupportedCollateralAsset(address(token1)));
        assertFalse(engine.isSupportedCollateralAsset(address(token2)));

        engine.addSupportedCollateralAsset(address(token1));
        assertTrue(engine.isSupportedCollateralAsset(address(token1)));
        assertFalse(engine.isSupportedCollateralAsset(address(token2)));
        assertFalse(engine.isSupportedCashAsset(address(token1)));

        engine.removeSupportedCollateralAsset(address(token1));
        assertFalse(engine.isSupportedCollateralAsset(address(token1)));
        assertFalse(engine.isSupportedCollateralAsset(address(token2)));

        engine.addSupportedCollateralAsset(address(token1));
        engine.addSupportedCollateralAsset(address(token2));

        assertTrue(engine.isSupportedCollateralAsset(address(token1)));
        assertTrue(engine.isSupportedCollateralAsset(address(token2)));
        assertFalse(engine.isSupportedCashAsset(address(token1)));
        assertFalse(engine.isSupportedCashAsset(address(token2)));
    }

    function test_addDuplicateAsset() public {
        engine.addSupportedCashAsset(address(token1));
        engine.addSupportedCollateralAsset(address(token2));

        vm.expectRevert(abi.encodeWithSelector(CashAssetAlreadySupported.selector, address(token1)));
        engine.addSupportedCashAsset(address(token1));

        vm.expectRevert(abi.encodeWithSelector(CollateralAssetAlreadySupported.selector, address(token2)));
        engine.addSupportedCollateralAsset(address(token2));
    }

    function test_removeNonExistentAsset() public {
        vm.expectRevert(abi.encodeWithSelector(CashAssetNotSupported.selector, address(token1)));
        engine.removeSupportedCashAsset(address(token1));

        vm.expectRevert(abi.encodeWithSelector(CollateralAssetNotSupported.selector, address(token2)));
        engine.removeSupportedCollateralAsset(address(token2));
    }

    function test_addRemoveCollateralAuth() public {
        startHoax(user1);

        vm.expectRevert(user1NotAuthorized);
        engine.addSupportedCollateralAsset(address(token1));

        vm.expectRevert(user1NotAuthorized);
        engine.removeSupportedCollateralAsset(address(token1));

        vm.stopPrank();
    }
    
    function test_addRemoveCash() public {
        assertFalse(engine.isSupportedCashAsset(address(token1)));
        assertFalse(engine.isSupportedCashAsset(address(token2)));

        engine.addSupportedCashAsset(address(token1));
        assertTrue(engine.isSupportedCashAsset(address(token1)));
        assertFalse(engine.isSupportedCashAsset(address(token2)));
        assertFalse(engine.isSupportedCollateralAsset(address(token1)));

        engine.removeSupportedCashAsset(address(token1));
        assertFalse(engine.isSupportedCashAsset(address(token1)));
        assertFalse(engine.isSupportedCashAsset(address(token2)));
        assertFalse(engine.isSupportedCollateralAsset(address(token1)));

        engine.addSupportedCashAsset(address(token1));
        engine.addSupportedCashAsset(address(token2));

        assertTrue(engine.isSupportedCashAsset(address(token1)));
        assertTrue(engine.isSupportedCashAsset(address(token2)));
        assertFalse(engine.isSupportedCollateralAsset(address(token1)));
        assertFalse(engine.isSupportedCollateralAsset(address(token2)));
    }

    function test_addRemoveCashAuth() public {
        startHoax(user1);

        vm.expectRevert(user1NotAuthorized);
        engine.addSupportedCashAsset(address(token1));

        vm.expectRevert(user1NotAuthorized);
        engine.removeSupportedCashAsset(address(token1));

        vm.stopPrank();
    }

    function test_addRemoveCollarLengths() public {
        assertFalse(engine.isValidCollarLength(1));
        assertFalse(engine.isValidCollarLength(2));

        engine.addSupportedCollarLength(1);
        assertTrue(engine.isValidCollarLength(1));
        assertFalse(engine.isValidCollarLength(2));

        engine.removeSupportedCollarLength(1);
        assertFalse(engine.isValidCollarLength(1));
        assertFalse(engine.isValidCollarLength(2));

        engine.addSupportedCollarLength(1);
        engine.addSupportedCollarLength(2);

        assertTrue(engine.isValidCollarLength(1));
        assertTrue(engine.isValidCollarLength(2));
    }

    function test_addRemoveCollarLengthsAuth() public {
        startHoax(user1);

        vm.expectRevert(user1NotAuthorized);
        engine.addSupportedCollarLength(1);

        vm.expectRevert(user1NotAuthorized);
        engine.removeSupportedCollarLength(1);

        vm.stopPrank();
    }

    /* >>> not unit tests - need to implement as integration tests <<<

    function test_getCurrentAssetPrice() public {
        engine.addSupportedCashAsset(address(token1));
        engine.addSupportedCollateralAsset(address(token2));

        uint256 cashPrice = engine.getCurrentAssetPrice(address(token1));
        uint256 collateralPrice = engine.getCurrentAssetPrice(address(token2));

        assertGt(cashPrice, 0);
        assertGt(collateralPrice, 0);
    } 
    
    */

    function test_getCurrentAssetPriceInvalidAsset() public {
        vm.expectRevert(abi.encodeWithSelector(AssetNotSupported.selector, address(token1)));
        engine.getCurrentAssetPrice(address(token1));
    }

    /* >>> not unit tests - need to implement as integration tests <<<

    function test_getHistoricalAssetPrice() public {
        engine.addSupportedCashAsset(address(token1));

        uint256 price = engine.getHistoricalAssetPrice(address(token1), 123456789);
        assertEq(price, 987654321);
    }

    function test_getHistoricalAssetPriceRemovedAsset() public {
        engine.addSupportedCashAsset(address(token1));
        engine.removeSupportedCashAsset(address(token1));

        uint256 price = engine.getHistoricalAssetPrice(address(token1), 123456789);
        assertEq(price, 987654321);
    }

    function test_notifyFinalized() public {
        assertTrue(false);
    }

    */

    function test_notifyFinalizedInvalidPool() public {
        vm.expectRevert(abi.encodeWithSelector(InvalidLiquidityPool.selector, address(pool1)));
        engine.notifyFinalized(address(pool1), bytes32(0));
    }

    function test_createVaultManager() public {
        startHoax(user1);

        address createdVaultManager = engine.createVaultManager();
        address storedVaultManager = engine.addressToVaultManager(user1);

        assertEq(createdVaultManager, storedVaultManager);

        address vaultManager = createdVaultManager;

        address vaultManagerOwner = MockVaultManager(vaultManager).owner();
        address vaultManagerUSer = MockVaultManager(vaultManager).user();
        address vaultManagerEngine = MockVaultManager(vaultManager).engine();

        assertEq(vaultManagerOwner, user1);
        assertEq(vaultManagerUSer, user1);
        assertEq(vaultManagerEngine, address(engine));

        vm.stopPrank();
    }

    function test_createDuplicateVaultManager() public {
        startHoax(user1);

        address vaultManager = engine.createVaultManager();

        vm.expectRevert(abi.encodeWithSelector(VaultManagerAlreadyExists.selector, user1, address(vaultManager)));
        engine.createVaultManager();

        vm.stopPrank();
    }
}