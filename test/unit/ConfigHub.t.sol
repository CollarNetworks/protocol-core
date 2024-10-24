// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { ConfigHub, IConfigHub, IERC20 } from "../../src/ConfigHub.sol";
import { ICollarTakerNFT } from "../../src/interfaces/ICollarTakerNFT.sol";
import { ICollarProviderNFT } from "../../src/interfaces/ICollarProviderNFT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ConfigHubTest is Test {
    TestERC20 token1;
    TestERC20 token2;
    ConfigHub configHub;
    uint constant durationToUse = 1 days;
    uint constant minDurationToUse = 300;
    uint constant maxDurationToUse = 365 days;
    uint constant ltvToUse = 9000;
    uint constant minLTVToUse = 1000;
    uint constant maxLTVToUse = 9999;
    address router = makeAddr("router");
    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address guardian = makeAddr("guardian");

    bytes user1NotAuthorized = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1);

    function setUp() public {
        token1 = new TestERC20("Test1", "TST1");
        token2 = new TestERC20("Test2", "TST2");
        configHub = new ConfigHub(owner);
    }

    function test_deploymentAndDeployParams() public {
        configHub = new ConfigHub(owner);
        assertEq(configHub.owner(), owner);
        assertEq(configHub.pendingOwner(), address(0));
        assertEq(configHub.VERSION(), "0.2.0");
        assertEq(address(configHub.ANY_ASSET()), address(type(uint160).max));
        assertEq(configHub.MIN_CONFIGURABLE_LTV_BIPS(), 1000);
        assertEq(configHub.MAX_CONFIGURABLE_LTV_BIPS(), 9999);
        assertEq(configHub.MIN_CONFIGURABLE_DURATION(), 300);
        assertEq(configHub.MAX_CONFIGURABLE_DURATION(), 5 * 365 days);
        assertFalse(configHub.isPauseGuardian(guardian));
        assertFalse(configHub.isPauseGuardian(owner));
        assertFalse(configHub.isPauseGuardian(address(0)));
        assertEq(configHub.feeRecipient(), address(0));
        assertEq(configHub.minDuration(), 0);
        assertEq(configHub.maxDuration(), 0);
        assertEq(configHub.protocolFeeAPR(), 0);
        assertEq(configHub.minLTV(), 0);
        assertEq(configHub.maxLTV(), 0);
    }

    function test_onlyOwnerAuth() public {
        startHoax(user1);

        vm.expectRevert(user1NotAuthorized);
        configHub.setCanOpenPair(token1, token2, address(0), true);

        vm.expectRevert(user1NotAuthorized);
        configHub.setLTVRange(0, 0);

        vm.expectRevert(user1NotAuthorized);
        configHub.setCollarDurationRange(0, 0);

        vm.expectRevert(user1NotAuthorized);
        configHub.setPauseGuardian(guardian, true);

        vm.expectRevert(user1NotAuthorized);
        configHub.setProtocolFeeParams(0, address(0));
    }

    function test_setCanOpenPair() public {
        startHoax(owner);
        address target = address(0x123);
        assertFalse(configHub.canOpenPair(token1, token2, target));
        assertFalse(configHub.canOpenSingle(token1, target));

        vm.expectEmit(address(configHub));
        emit IConfigHub.ContractCanOpenSet(token1, token2, target, true);
        configHub.setCanOpenPair(token1, token2, target, true);

        assertTrue(configHub.canOpenPair(token1, token2, target));
        assertFalse(configHub.canOpenPair(token2, token1, target));
        assertFalse(configHub.canOpenSingle(token1, target));
        assertFalse(configHub.canOpenSingle(token2, target));

        // disabling
        vm.expectEmit(address(configHub));
        emit IConfigHub.ContractCanOpenSet(token1, token2, target, false);
        configHub.setCanOpenPair(token1, token2, target, false);

        assertFalse(configHub.canOpenPair(token1, token2, target));
        assertFalse(configHub.canOpenPair(token2, token1, target));
        assertFalse(configHub.canOpenSingle(token1, target));
        assertFalse(configHub.canOpenSingle(token2, target));

        // canOpenSingle
        vm.expectEmit(address(configHub));
        IERC20 anyAsset = configHub.ANY_ASSET();
        emit IConfigHub.ContractCanOpenSet(token1, anyAsset, target, true);
        configHub.setCanOpenPair(token1, anyAsset, target, true);

        // true
        assertTrue(configHub.canOpenPair(token1, anyAsset, target));
        assertTrue(configHub.canOpenSingle(token1, target));
        // false
        assertFalse(configHub.canOpenPair(token2, token1, target));
        assertFalse(configHub.canOpenSingle(token2, target));
    }

    function test_isValidDuration() public {
        startHoax(owner);
        configHub.setCollarDurationRange(minDurationToUse, maxDurationToUse);
        assertFalse(configHub.isValidCollarDuration(minDurationToUse - 1));
        assertTrue(configHub.isValidCollarDuration(minDurationToUse));
        assertTrue(configHub.isValidCollarDuration(maxDurationToUse));
        assertFalse(configHub.isValidCollarDuration(maxDurationToUse + 1));
    }

    function test_isValidLTV() public {
        startHoax(owner);
        configHub.setLTVRange(minLTVToUse, maxLTVToUse);
        assertFalse(configHub.isValidLTV(minLTVToUse - 1));
        assertTrue(configHub.isValidLTV(minLTVToUse));
        assertTrue(configHub.isValidLTV(maxLTVToUse));
        assertFalse(configHub.isValidLTV(maxLTVToUse + 1));
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

    function test_setPauseGuardian() public {
        address[] memory expectedGuardians = new address[](0);
        assertEq(configHub.allPauseGuardians(), expectedGuardians);

        startHoax(owner);
        vm.expectEmit(address(configHub));
        emit IConfigHub.PauseGuardianSet(guardian, true);
        configHub.setPauseGuardian(guardian, true);
        assertTrue(configHub.isPauseGuardian(guardian));

        expectedGuardians = new address[](1);
        expectedGuardians[0] = guardian;
        assertEq(configHub.allPauseGuardians(), expectedGuardians);

        // set another
        vm.expectEmit(address(configHub));
        address anotherGuardian = makeAddr("anotherGuardian");
        emit IConfigHub.PauseGuardianSet(anotherGuardian, true);
        configHub.setPauseGuardian(anotherGuardian, true);
        assertTrue(configHub.isPauseGuardian(anotherGuardian));
        // previous is still set
        assertTrue(configHub.isPauseGuardian(guardian));

        expectedGuardians = new address[](2);
        expectedGuardians[0] = guardian;
        expectedGuardians[1] = anotherGuardian;
        assertEq(configHub.allPauseGuardians(), expectedGuardians);

        vm.expectEmit(address(configHub));
        emit IConfigHub.PauseGuardianSet(guardian, false);
        configHub.setPauseGuardian(guardian, false);
        assertFalse(configHub.isPauseGuardian(guardian));
        // the other is still set
        assertTrue(configHub.isPauseGuardian(anotherGuardian));

        expectedGuardians = new address[](1);
        expectedGuardians[0] = anotherGuardian;
        assertEq(configHub.allPauseGuardians(), expectedGuardians);
    }

    function test_setProtocolFeeParams() public {
        startHoax(owner);

        // reverts
        vm.expectRevert("fee APR too high");
        configHub.setProtocolFeeParams(100 + 1, address(0)); // more than 1%

        vm.expectRevert("must set recipient for non-zero APR");
        configHub.setProtocolFeeParams(1, address(0));

        // effects
        vm.expectEmit(address(configHub));
        uint apr = 1;
        emit IConfigHub.ProtocolFeeParamsUpdated(0, apr, address(0), user1);
        configHub.setProtocolFeeParams(1, user1);
        assertEq(configHub.protocolFeeAPR(), apr);
        assertEq(configHub.feeRecipient(), user1);

        // unset
        vm.expectEmit(address(configHub));
        emit IConfigHub.ProtocolFeeParamsUpdated(apr, 0, user1, address(0));
        configHub.setProtocolFeeParams(0, address(0));
        assertEq(configHub.protocolFeeAPR(), 0);
        assertEq(configHub.feeRecipient(), address(0));
    }
}
