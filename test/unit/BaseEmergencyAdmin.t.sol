// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { ERC721, IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20Errors } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { TestERC20 } from "../utils/TestERC20.sol";
import { MockConfigHub } from "../../test/utils/MockConfigHub.sol";
import { MockUniRouter } from "../../test/utils/MockUniRouter.sol";

import { BaseEmergencyAdmin } from "../../src/base/BaseEmergencyAdmin.sol";
import { ConfigHub } from "../../src/ConfigHub.sol";

contract TestableBaseEmergencyAdmin is BaseEmergencyAdmin {
    constructor(address _initialOwner, ConfigHub _configHub) BaseEmergencyAdmin(_initialOwner, _configHub) {}
    // non abstract
    function pausableMethod() external whenNotPaused {}
    function unPausableMethod() external {}
}

contract BaseEmergencyAdminTest is Test {
    TestERC20 erc20;
    MockConfigHub configHub;
    MockUniRouter uniRouter;

    BaseEmergencyAdmin sut;

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address guardian = makeAddr("guardian");

    function setUp() public {
        erc20 = new TestERC20("TestERC20", "TestERC20");
        uniRouter = new MockUniRouter();
        configHub = new MockConfigHub(owner, address(uniRouter));

        sut = new TestableBaseEmergencyAdmin(owner, configHub);

        vm.label(address(erc20), "TestERC20");
        vm.label(address(configHub), "ConfigHub");
        vm.label(address(uniRouter), "UniRouter");
    }

    function test_constructor() public {
        assertEq(sut.owner(), owner);
        assertEq(address(sut.configHub()), address(configHub));
    }

    function test_pauseByGuardian() public {
        vm.prank(owner);
        configHub.setPauseGuardian(guardian);

        vm.prank(guardian);
        vm.expectEmit(address(sut));
        emit Pausable.Paused(guardian);
        vm.expectEmit(address(sut));
        emit BaseEmergencyAdmin.PausedByGuardian(guardian);
        sut.pauseByGuardian();

        assertTrue(sut.paused());
    }

    function test_pause() public {
        vm.prank(owner);
        vm.expectEmit(address(sut));
        emit Pausable.Paused(owner);
        sut.pause();

        assertTrue(sut.paused());
    }

    function test_unpause() public {
        vm.startPrank(owner);
        sut.pause();
        vm.expectEmit(address(sut));
        emit Pausable.Unpaused(owner);
        sut.unpause();
        vm.stopPrank();

        assertFalse(sut.paused());
    }

    function test_setConfigHub() public {
        ConfigHub newConfigHub = new ConfigHub(owner, address(0));

        vm.prank(owner);
        vm.expectEmit(address(sut));
        emit BaseEmergencyAdmin.ConfigHubUpdated(configHub, newConfigHub);
        sut.setConfigHub(newConfigHub);

        assertEq(address(sut.configHub()), address(newConfigHub));
    }

    function test_rescueTokens_ERC20() public {
        uint256 amount = 1000;
        erc20.mint(address(sut), amount);

        vm.prank(owner);
        vm.expectEmit(address(sut));
        emit BaseEmergencyAdmin.TokensRescued(address(erc20), amount);
        sut.rescueTokens(address(erc20), amount);

        assertEq(erc20.balanceOf(owner), amount);
        assertEq(erc20.balanceOf(address(sut)), 0);
    }

    function test_pausableMethods() public virtual {
        TestableBaseEmergencyAdmin tSut = TestableBaseEmergencyAdmin(address(sut));
        tSut.pausableMethod();

        vm.prank(owner);
        tSut.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        tSut.pausableMethod();

        tSut.unPausableMethod(); // Should work even when paused
    }

    // reverts

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

    function test_revert_setConfigHub_invalidConfigHub() public {
        vm.startPrank(owner);

        vm.expectRevert(new bytes(0));
        sut.setConfigHub(ConfigHub(address(0)));

        ConfigHub badHub = ConfigHub(address(new BadConfigHub1()));
        vm.expectRevert();
        sut.setConfigHub(badHub);

        badHub = ConfigHub(address(new BadConfigHub2()));
        vm.expectRevert("unexpected version length");
        sut.setConfigHub(badHub);
    }

    function test_onlyOwnerMethods() public {
        startHoax(user1);
        bytes4 selector = Ownable.OwnableUnauthorizedAccount.selector;

        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        sut.pause();

        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        sut.unpause();

        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        sut.setConfigHub(configHub);

        vm.expectRevert(abi.encodeWithSelector(selector, user1));
        sut.rescueTokens(address(0), 0);
    }

    function test_revert_pauseByGuardian_notGuardian() public {
        vm.prank(user1);
        vm.expectRevert("not guardian");
        sut.pauseByGuardian();

        vm.prank(owner);
        configHub.setPauseGuardian(user1);
        vm.prank(user1);
        sut.pauseByGuardian();
        assertTrue(sut.paused());
    }

    function test_revert_pauseByGuardian_ownerRenounced() public {
        vm.prank(owner);
        configHub.setPauseGuardian(guardian);

        vm.prank(owner);
        sut.renounceOwnership();

        vm.prank(guardian);
        vm.expectRevert("owner renounced");
        sut.pauseByGuardian();
    }
}

contract BadConfigHub1 {
    fallback() external {}
}

contract BadConfigHub2 {
    function VERSION() external returns (string memory) {}
}
