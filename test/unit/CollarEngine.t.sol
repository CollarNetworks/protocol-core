// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockUniRouter } from "../utils/MockUniRouter.sol";

import { CollarEngine } from "../../src/implementations/CollarEngine.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract CollarEngineTest is Test {
    TestERC20 token1;
    TestERC20 token2;
    MockUniRouter router;
    CollarEngine engine;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    // below we copy error messages from contracts since they aren't by default "public" or otherwise
    // accessible

    error OwnableUnauthorizedAccount(address account);

    bytes user1NotAuthorized = abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(user1));

    function setUp() public {
        token1 = new TestERC20("Test1", "TST1");
        token2 = new TestERC20("Test2", "TST2");
        router = new MockUniRouter();

        engine = new CollarEngine(address(router));
        engine.addLTV(9000);
    }

    function test_deploymentAndDeployParams() public view {
        assertEq(address(engine.univ3SwapRouter()), address(router));
        assertEq(engine.owner(), address(this));
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
        vm.expectRevert("already added");
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
        vm.expectRevert("not found");
        engine.removeSupportedCashAsset(address(token1));

        vm.expectRevert("not found");
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
        vm.expectRevert("already added");
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

    function test_addCollarDuration_AlreadyAdded() public {
        uint duration = 7 days;

        // First addition should succeed
        engine.addCollarDuration(duration);
        assertTrue(engine.isValidCollarDuration(duration));

        // Second addition should fail
        vm.expectRevert("already added");
        engine.addCollarDuration(duration);
    }

    function test_removeCollarDuration() public {
        engine.addCollarDuration(1);
        engine.removeCollarDuration(1);
        assertFalse(engine.isValidCollarDuration(1));
    }

    function test_removeCollarDuration_NotFound() public {
        uint duration = 7 days;
        vm.expectRevert("not found");
        engine.removeCollarDuration(duration);
    }

    function test_removeCollarDuration_NoAuth() public {
        startHoax(user1);
        vm.expectRevert(user1NotAuthorized);
        engine.removeCollarDuration(1);
        vm.stopPrank();
    }

    function test_getHistoricalAssetPriceViaTWAP_InvalidAsset() public {
        vm.expectRevert("not supported");
        engine.getHistoricalAssetPriceViaTWAP(address(token1), address(token2), 0, 0);
    }

    function test_removeLTV() public {
        engine.removeLTV(9000);
        assertFalse(engine.isValidLTV(9000));
    }

    function test_removeLTV_NotFound() public {
        uint ltv = 7500;
        vm.expectRevert("not found");
        engine.removeLTV(ltv);
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

    function test_addLTV_AlreadyAdded() public {
        uint ltv = 8500;

        // First addition should succeed
        engine.addLTV(ltv);
        assertTrue(engine.isValidLTV(ltv));

        // Second addition should fail
        vm.expectRevert("already added");
        engine.addLTV(ltv);
    }

    function test_setCollarTakerContractAuth() public {
        address testContract = address(0x123);
        engine.setCollarTakerContractAuth(testContract, true);
        assertTrue(engine.isCollarTakerNFT(testContract));

        // Test "already added" branch
        engine.setCollarTakerContractAuth(testContract, false);
        assertFalse(engine.isCollarTakerNFT(testContract));
    }

    function test_setProviderContractAuth() public {
        address testContract = address(0x456);
        engine.setProviderContractAuth(testContract, true);
        assertTrue(engine.isProviderNFT(testContract));

        // Test "already added" branch
        engine.setProviderContractAuth(testContract, false);
        assertFalse(engine.isProviderNFT(testContract));
    }
}
