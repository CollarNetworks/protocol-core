// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { TestERC20 } from "../utils/TestERC20.sol";

contract CollarVaultManagerTest is Test {
    TestERC20 token1;
    TestERC20 token2;

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    // below we copy error messages from contracts since they aren't by default "public" or otherwise accessible

    error OwnableUnauthorizedAccount(address account);
    bytes user1NotAuthorized = abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(user1));

    function setUp() public {
        token1 = new TestERC20("Test1", "TST1");
        token2 = new TestERC20("Test2", "TST2");
    }

    function test_deploymentAndDeployParams() public {
        revert("TODO");
    }

    function test_openVault() public {
        revert("TODO");
    }

    function test_openVault_DuplicateOptions() public {
        revert("TODO");
    }

    function test_openVault_InvalidAssetSpecifiers() public {
        revert("TODO");
    }

    function test_openVault_InvalidCollarOpts() public {
        revert("TODO");
    }

    function test_openVault_InvalidLiquidityOpts() public {
        revert("TODO");
    }

    function test_openVault_NotEnoughAssets() public {
        revert("TODO");
    }

    function test_openVault_NoAssetPermissiosn() public {
        revert("TODO");
    }

    function test_openVault_NoAuth() public {
        revert("TODO");
    }

    function test_closeVault() public {
        revert("TODO");
    }

    function test_closeVault_AlreadyClosed() public {
        revert("TODO");
    }

    function test_closeVault_InvalidVault() public {
        revert("TODO");
    }

    function test_closeVault_NotExpired() public {
        revert("TODO");
    }

    function test_redeem() public {
        revert("TODO");
    }

    function test_redeem_InvalidVault() public {
        revert("TODO");
    }

    function test_redeem_InvalidAmount() public {
        revert("TODO");
    }

    function test_redeem_NotFinalized() public {
        revert("TODO");
    }

    function test_redeem_NotApproved() public {
        revert("TODO");
    }

    function test_previewRedeem() public {
        revert("TODO");
    }

    function test_previewRedeem_NotFinalized() public {
        revert("TODO");
    }

    function test_previewRedeem_InvalidVault() public {
        revert("TODO");
    }

    function test_previewRedeem_InvalidAmount() public {
        revert("TODO");
    }

    function test_withdraw() public {
        revert("TODO");
    }

    function test_withdraw_TooMuch() public {
        revert("TODO");
    }

    function test_withdraw_NoAuth() public {
        revert("TODO");
    }

    function test_withdraw_InvalidVault() public {
        revert("TODO");
    }

    function test_vaultInfo() public {
        revert("TODO");
    }

    function test_vaultInfo_InvalidVault() public {
        revert("TODO");
    }
}