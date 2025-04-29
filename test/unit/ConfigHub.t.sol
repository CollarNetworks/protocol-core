// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { ConfigHub, IConfigHub } from "../../src/ConfigHub.sol";
import { ICollarTakerNFT } from "../../src/interfaces/ICollarTakerNFT.sol";
import { ICollarProviderNFT } from "../../src/interfaces/ICollarProviderNFT.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract ConfigHubTest is Test {
    address token1;
    address token2;
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

    bytes user1NotAuthorized = abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user1);

    function setUp() public {
        token1 = address(new TestERC20("Test1", "TST1", 18));
        token2 = address(new TestERC20("Test2", "TST2", 18));
        configHub = new ConfigHub(owner);
    }

    function test_deploymentAndDeployParams() public {
        configHub = new ConfigHub(owner);
        assertEq(configHub.owner(), owner);
        assertEq(configHub.pendingOwner(), address(0));
        assertEq(configHub.VERSION(), "0.3.0");
        assertEq(configHub.ANY_ASSET(), address(type(uint160).max));
        assertEq(configHub.MIN_CONFIGURABLE_LTV_BIPS(), 1000);
        assertEq(configHub.MAX_CONFIGURABLE_LTV_BIPS(), 9999);
        assertEq(configHub.MIN_CONFIGURABLE_DURATION(), 300);
        assertEq(configHub.MAX_CONFIGURABLE_DURATION(), 5 * 365 days);
        assertEq(configHub.MAX_PROTOCOL_FEE_BIPS(), 100);
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
        configHub.setProtocolFeeParams(0, address(0));
    }

    function test_setCanOpenPair() public {
        startHoax(owner);
        address target = address(0x123);
        assertFalse(configHub.canOpenPair(token1, token2, target));
        assertFalse(configHub.canOpenSingle(token1, target));
        // empty
        assertEq(configHub.allCanOpenPair(token1, token2), new address[](0));

        vm.expectEmit(address(configHub));
        emit IConfigHub.ContractCanOpenSet(token1, token2, target, true);
        configHub.setCanOpenPair(token1, token2, target, true);

        assertTrue(configHub.canOpenPair(token1, token2, target));
        assertFalse(configHub.canOpenPair(token2, token1, target));
        assertFalse(configHub.canOpenSingle(token1, target));
        assertFalse(configHub.canOpenSingle(token2, target));

        // check array view
        address[] memory targetOnly = new address[](1);
        targetOnly[0] = target;
        // has target
        assertEq(configHub.allCanOpenPair(token1, token2), targetOnly);
        // others are empty
        assertEq(configHub.allCanOpenPair(token1, token1), new address[](0));
        assertEq(configHub.allCanOpenPair(token2, token1), new address[](0));
        assertEq(configHub.allCanOpenPair(token1, configHub.ANY_ASSET()), new address[](0));
        assertEq(configHub.allCanOpenPair(token2, configHub.ANY_ASSET()), new address[](0));

        // disabling
        vm.expectEmit(address(configHub));
        emit IConfigHub.ContractCanOpenSet(token1, token2, target, false);
        configHub.setCanOpenPair(token1, token2, target, false);

        assertFalse(configHub.canOpenPair(token1, token2, target));
        assertFalse(configHub.canOpenPair(token2, token1, target));
        assertFalse(configHub.canOpenSingle(token1, target));
        assertFalse(configHub.canOpenSingle(token2, target));
        // array view
        assertEq(configHub.allCanOpenPair(token1, token2), new address[](0));

        // canOpenSingle
        vm.expectEmit(address(configHub));
        address anyAsset = configHub.ANY_ASSET();
        emit IConfigHub.ContractCanOpenSet(token1, anyAsset, target, true);
        configHub.setCanOpenPair(token1, anyAsset, target, true);

        // true
        assertTrue(configHub.canOpenPair(token1, anyAsset, target));
        assertTrue(configHub.canOpenSingle(token1, target));
        // false
        assertFalse(configHub.canOpenPair(token2, token1, target));
        assertFalse(configHub.canOpenSingle(token2, target));
        // array view
        assertEq(configHub.allCanOpenPair(token1, token2), new address[](0));
        assertEq(configHub.allCanOpenPair(token1, configHub.ANY_ASSET()), targetOnly);
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
        vm.expectRevert("LTV min > max");
        configHub.setLTVRange(maxLTVToUse, minLTVToUse);

        vm.expectRevert("LTV min too low");
        configHub.setLTVRange(0, maxLTVToUse);

        vm.expectRevert("LTV max too high");
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
        vm.expectRevert("duration min > max");
        configHub.setCollarDurationRange(maxDurationToUse, minDurationToUse);

        vm.expectRevert("duration min too low");
        configHub.setCollarDurationRange(0, maxDurationToUse);

        vm.expectRevert("duration max too high");
        configHub.setCollarDurationRange(minDurationToUse, 10 * 365 days);
    }

    function test_setProtocolFeeParams() public {
        startHoax(owner);

        // reverts
        vm.expectRevert("protocol fee APR too high");
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
