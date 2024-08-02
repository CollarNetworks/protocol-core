// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { TestERC20 } from "../utils/TestERC20.sol";

import { BaseEmergencyAdmin } from "../../src/base/BaseEmergencyAdmin.sol";
import { ConfigHub } from "../../src/ConfigHub.sol";

// base contract for other tests that will check this functionality
abstract contract BaseEmergencyAdminTestBase is Test {
    TestERC20 erc20;
    ConfigHub configHub;

    BaseEmergencyAdmin testedContract;

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address guardian = makeAddr("guardian");

    function setUp() public virtual {
        erc20 = new TestERC20("TestERC20", "TestERC20");
        configHub = new ConfigHub(owner);

        setupTestedContract();

        vm.label(address(erc20), "TestERC20");
        vm.label(address(configHub), "ConfigHub");
    }

    /// @dev this is virtual to be filled by inheriting test contracts
    function setupTestedContract() internal virtual;

    function test_constructor() public {
        setupTestedContract();
        assertEq(testedContract.owner(), owner);
        assertEq(address(testedContract.configHub()), address(configHub));
    }

    function test_pauseByGuardian() public {
        vm.prank(owner);
        configHub.setPauseGuardian(guardian);

        vm.prank(guardian);
        vm.expectEmit(address(testedContract));
        emit Pausable.Paused(guardian);
        vm.expectEmit(address(testedContract));
        emit BaseEmergencyAdmin.PausedByGuardian(guardian);
        testedContract.pauseByGuardian();

        assertTrue(testedContract.paused());
    }

    function test_pause() public {
        vm.prank(owner);
        vm.expectEmit(address(testedContract));
        emit Pausable.Paused(owner);
        testedContract.pause();

        assertTrue(testedContract.paused());
    }

    function test_unpause() public {
        vm.startPrank(owner);
        testedContract.pause();
        vm.expectEmit(address(testedContract));
        emit Pausable.Unpaused(owner);
        testedContract.unpause();
        vm.stopPrank();

        assertFalse(testedContract.paused());
    }

    function test_setConfigHub() public {
        ConfigHub newConfigHub = new ConfigHub(owner);

        vm.prank(owner);
        vm.expectEmit(address(testedContract));
        emit BaseEmergencyAdmin.ConfigHubUpdated(configHub, newConfigHub);
        testedContract.setConfigHub(newConfigHub);

        assertEq(address(testedContract.configHub()), address(newConfigHub));
    }

    function test_rescueTokens_ERC20() public {
        uint amount = 1000;
        erc20.mint(address(testedContract), amount);

        vm.prank(owner);
        vm.expectEmit(address(testedContract));
        emit BaseEmergencyAdmin.TokensRescued(address(erc20), amount);
        testedContract.rescueTokens(address(erc20), amount);

        assertEq(erc20.balanceOf(owner), amount);
        assertEq(erc20.balanceOf(address(testedContract)), 0);
    }

    // reverts

    function test_revert_setConfigHub_invalidConfigHub() public {
        vm.startPrank(owner);

        vm.expectRevert(new bytes(0));
        testedContract.setConfigHub(ConfigHub(address(0)));

        ConfigHub badHub = ConfigHub(address(new BadConfigHub1()));
        vm.expectRevert(new bytes(0));
        testedContract.setConfigHub(badHub);

        badHub = ConfigHub(address(new BadConfigHub2()));
        vm.expectRevert("unexpected version length");
        testedContract.setConfigHub(badHub);
    }

    function test_onlyOwnerMethods() public {
        startHoax(user1);
        bytes4 selector = Ownable.OwnableUnauthorizedAccount.selector;

        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        testedContract.pause();

        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        testedContract.unpause();

        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        testedContract.setConfigHub(configHub);

        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        testedContract.rescueTokens(address(0), 0);
    }

    function test_revert_pauseByGuardian_notGuardian() public {
        vm.prank(user1);
        vm.expectRevert("not guardian");
        testedContract.pauseByGuardian();

        vm.prank(owner);
        configHub.setPauseGuardian(user1);
        vm.prank(user1);
        testedContract.pauseByGuardian();
        assertTrue(testedContract.paused());
    }

    function test_revert_pauseByGuardian_ownerRenounced() public {
        vm.prank(owner);
        configHub.setPauseGuardian(guardian);

        vm.prank(owner);
        testedContract.renounceOwnership();

        vm.prank(guardian);
        vm.expectRevert("owner renounced");
        testedContract.pauseByGuardian();
    }

    function test_revert_guardian_unpause() public {
        vm.prank(owner);
        configHub.setPauseGuardian(guardian);

        vm.startPrank(guardian);
        // can pause
        testedContract.pauseByGuardian();
        // cannot unpause
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, guardian));
        testedContract.unpause();
    }
}

contract BadConfigHub1 {
    fallback() external { }
}

contract BadConfigHub2 {
    function VERSION() external returns (string memory) { }
}

// mock of an inheriting contract (because base is abstract)
contract TestableBaseEmergencyAdmin is BaseEmergencyAdmin {
    constructor(address _initialOwner, ConfigHub _configHub) BaseEmergencyAdmin(_initialOwner) {
        _setConfigHub(_configHub);
    }
}

// the tests for the mock contract
contract BaseEmergencyAdminMockTest is BaseEmergencyAdminTestBase {
    function setupTestedContract() internal override {
        testedContract = new TestableBaseEmergencyAdmin(owner, configHub);
    }

    function test_revert_constructor_invalidConfigHub() public {
        vm.expectRevert(new bytes(0));
        new TestableBaseEmergencyAdmin(owner, ConfigHub(address(0)));

        ConfigHub badHub = ConfigHub(address(new BadConfigHub1()));
        vm.expectRevert();
        new TestableBaseEmergencyAdmin(owner, badHub);

        badHub = ConfigHub(address(new BadConfigHub2()));
        vm.expectRevert("unexpected version length");
        new TestableBaseEmergencyAdmin(owner, badHub);
    }
}
