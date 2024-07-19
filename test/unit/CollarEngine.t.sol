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
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
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

    function test_isValidDuration() public view {
        assertFalse(engine.isValidCollarDuration(1));
        assertTrue(engine.isValidCollarDuration(301));
        assertFalse(engine.isValidCollarDuration(366 days));
    }

    function test_getHistoricalAssetPriceViaTWAP_InvalidAsset() public {
        vm.expectRevert("not supported");
        engine.getHistoricalAssetPriceViaTWAP(address(token1), address(token2), 0, 0);
    }

    function test_isValidLTV() public view {
        assertFalse(engine.isValidLTV(100));
        assertTrue(engine.isValidLTV(9000));
        assertFalse(engine.isValidLTV(10_000));
    }

    function test_setCollarTakerContractAuth_non_taker_contract() public {
        address testContract = address(0x123);
        // testContract doesnt support calling .cashAsset();
        vm.expectRevert();
        engine.setCollarTakerContractAuth(testContract, true);
        assertFalse(engine.isCollarTakerNFT(testContract));
    }

    function test_setProviderContractAuth_non_taker_contract() public {
        address testContract = address(0x456);
        // testContract doesnt support calling .cashAsset();
        vm.expectRevert();
        engine.setProviderContractAuth(testContract, true);
        assertFalse(engine.isProviderNFT(testContract));
    }

    function test_setMaxLTV() public {
        engine.setMaxLTV(1000);
        assertEq(engine.MAX_LTV(), 1000);
    }

    function test_setMinLTV() public {
        engine.setMinLTV(1000);
        assertEq(engine.MIN_LTV(), 1000);
    }

    function test_setMinCollarDuration() public {
        engine.setMinCollarDuration(1000);
        assertEq(engine.MIN_COLLAR_DURATION(), 1000);
    }

    function test_setMaxCollarDuration() public {
        engine.setMaxCollarDuration(1000);
        assertEq(engine.MAX_COLLAR_DURATION(), 1000);
    }
}
