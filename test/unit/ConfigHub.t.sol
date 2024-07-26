// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockUniRouter } from "../utils/MockUniRouter.sol";

import { IConfigHub } from "../../src/interfaces/IConfigHub.sol";
import { ConfigHub } from "../../src/implementations/ConfigHub.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ConfigHubTest is Test {
    TestERC20 token1;
    TestERC20 token2;
    MockUniRouter router;
    ConfigHub configHub;
    uint constant durationToUse = 1 days;
    uint constant minDurationToUse = 300;
    uint constant maxDurationToUse = 365 days;
    uint constant ltvToUse = 9000;
    uint constant minLTVToUse = 1000;
    uint constant maxLTVToUse = 9999;
    address owner = makeAddr("owner");
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

        configHub = new ConfigHub(owner, address(router));
    }

    function test_deploymentAndDeployParams() public view {
        assertEq(address(configHub.univ3SwapRouter()), address(router));
        assertEq(configHub.owner(), owner);
    }

    function test_addSupportedCashAsset() public {
        startHoax(owner);
        assertFalse(configHub.isSupportedCashAsset(address(token1)));
        configHub.setCashAssetSupport(address(token1), true);
        assertTrue(configHub.isSupportedCashAsset(address(token1)));
    }

    function test_addSupportedCashAsset_NoAuth() public {
        startHoax(user1);
        vm.expectRevert(user1NotAuthorized);
        configHub.setCashAssetSupport(address(token1), true);
        vm.stopPrank();
    }

    function test_removeSupportedCashAsset() public {
        startHoax(owner);
        configHub.setCashAssetSupport(address(token1), true);
        configHub.setCashAssetSupport(address(token1), false);
        assertFalse(configHub.isSupportedCashAsset(address(token1)));
    }

    function test_removeSupportedCashAsset_NoAuth() public {
        startHoax(user1);
        vm.expectRevert(user1NotAuthorized);
        configHub.setCashAssetSupport(address(token1), false);
        vm.stopPrank();
    }

    function test_addSupportedCollateralAsset() public {
        startHoax(owner);
        assertFalse(configHub.isSupportedCollateralAsset(address(token1)));
        configHub.setCollateralAssetSupport(address(token1), true);
        assertTrue(configHub.isSupportedCollateralAsset(address(token1)));
    }

    function test_addSupportedCollateralAsset_NoAuth() public {
        startHoax(user1);
        vm.expectRevert(user1NotAuthorized);
        configHub.setCollateralAssetSupport(address(token1), true);
        vm.stopPrank();
    }

    function test_removeSupportedCollateralAsset() public {
        startHoax(owner);
        configHub.setCollateralAssetSupport(address(token1), true);
        configHub.setCollateralAssetSupport(address(token1), false);
        assertFalse(configHub.isSupportedCollateralAsset(address(token1)));
    }

    function test_removeSupportedCollateralAsset_NoAuth() public {
        startHoax(user1);
        vm.expectRevert(user1NotAuthorized);
        configHub.setCollateralAssetSupport(address(token1), false);
        vm.stopPrank();
    }

    function test_isValidDuration() public {
        startHoax(owner);
        configHub.setCollarDurationRange(minDurationToUse, maxDurationToUse);
        assertFalse(configHub.isValidCollarDuration(minDurationToUse - 1));
        assertTrue(configHub.isValidCollarDuration(minDurationToUse));
        assertFalse(configHub.isValidCollarDuration(maxDurationToUse + 1));
    }

    function test_getHistoricalAssetPriceViaTWAP_InvalidAsset() public {
        vm.expectRevert("not supported");
        configHub.getHistoricalAssetPriceViaTWAP(address(token1), address(token2), 0, 0);
        startHoax(owner);
        configHub.setCashAssetSupport(address(token1), true);
        vm.expectRevert("not supported");
        configHub.getHistoricalAssetPriceViaTWAP(address(token1), address(token2), 0, 0);
    }

    function test_isValidLTV() public {
        startHoax(owner);
        configHub.setLTVRange(minLTVToUse, maxLTVToUse);
        assertFalse(configHub.isValidLTV(minLTVToUse - 1));
        assertTrue(configHub.isValidLTV(maxLTVToUse));
        assertFalse(configHub.isValidLTV(maxLTVToUse + 1));
    }

    function test_setCollarTakerContractAuth_non_taker_contract() public {
        startHoax(owner);
        address testContract = address(0x123);
        // testContract doesnt support calling .cashAsset();
        vm.expectRevert();
        configHub.setCollarTakerContractAuth(testContract, true);
        assertFalse(configHub.isCollarTakerNFT(testContract));
    }

    function test_setProviderContractAuth_non_taker_contract() public {
        startHoax(owner);
        address testContract = address(0x456);
        // testContract doesnt support calling .cashAsset();
        vm.expectRevert();
        configHub.setProviderContractAuth(testContract, true);
        assertFalse(configHub.isProviderNFT(testContract));
    }

    function test_setLTVRange() public {
        startHoax(owner);
        vm.expectEmit(address(configHub));
        emit IConfigHub.LTVRangeSet(minLTVToUse, maxLTVToUse);
        configHub.setLTVRange(minLTVToUse, maxLTVToUse);
        assertEq(configHub.minLTV(), minLTVToUse);
        assertEq(configHub.maxLTV(), maxLTVToUse);
    }

    function test_revert_setLTVRange() public {
        startHoax(owner);
        vm.expectRevert("min > max");
        configHub.setLTVRange(maxLTVToUse, minLTVToUse);

        vm.expectRevert("min too low");
        configHub.setLTVRange(0, maxLTVToUse);

        vm.expectRevert("max too high");
        configHub.setLTVRange(minLTVToUse, 10_000);
    }

    function test_setDurationRange() public {
        startHoax(owner);
        vm.expectEmit(address(configHub));
        emit IConfigHub.CollarDurationRangeSet(minLTVToUse, maxDurationToUse);
        configHub.setCollarDurationRange(minLTVToUse, maxDurationToUse);
        assertEq(configHub.minDuration(), minLTVToUse);
        assertEq(configHub.maxDuration(), maxDurationToUse);
    }

    function test_revert_setCollarDurationRange() public {
        startHoax(owner);
        vm.expectRevert("min > max");
        configHub.setCollarDurationRange(maxDurationToUse, minDurationToUse);

        vm.expectRevert("min too low");
        configHub.setCollarDurationRange(0, maxDurationToUse);

        vm.expectRevert("max too high");
        configHub.setCollarDurationRange(minDurationToUse, 10 * 365 days);
    }
}
