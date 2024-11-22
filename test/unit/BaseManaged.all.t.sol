// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { TestERC20 } from "../utils/TestERC20.sol";
import { MockChainlinkFeed } from "../utils/MockChainlinkFeed.sol";

import { BaseManaged } from "../../src/base/BaseManaged.sol";
import { ConfigHub } from "../../src/ConfigHub.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { CollarProviderNFT } from "../../src/CollarProviderNFT.sol";
import { EscrowSupplierNFT } from "../../src/EscrowSupplierNFT.sol";
import { LoansNFT } from "../../src/LoansNFT.sol";
import { Rolls } from "../../src/Rolls.sol";
import { ChainlinkOracle } from "../../src/ChainlinkOracle.sol";

contract TestERC721 is ERC721 {
    constructor() ERC721("TestERC721", "TestERC721") { }

    function mint(address to, uint id) external {
        _mint(to, id);
    }
}

// base contract for other tests that will check this functionality
abstract contract BaseManagedTestBase is Test {
    TestERC20 erc20;
    TestERC721 erc721;
    ConfigHub configHub;

    BaseManaged testedContract;

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address guardian = makeAddr("guardian");

    function setUp() public virtual {
        erc20 = new TestERC20("TestERC20", "TestERC20");
        erc721 = new TestERC721();
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
        configHub.setPauseGuardian(guardian, true);

        vm.prank(guardian);
        vm.expectEmit(address(testedContract));
        emit Pausable.Paused(guardian);
        vm.expectEmit(address(testedContract));
        emit BaseManaged.PausedByGuardian(guardian);
        testedContract.pauseByGuardian();

        assertTrue(testedContract.paused());

        // unset
        vm.startPrank(owner);
        testedContract.unpause();
        configHub.setPauseGuardian(guardian, false);

        vm.startPrank(guardian);
        vm.expectRevert("not guardian");
        testedContract.pauseByGuardian();
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
        emit BaseManaged.ConfigHubUpdated(configHub, newConfigHub);
        testedContract.setConfigHub(newConfigHub);

        assertEq(address(testedContract.configHub()), address(newConfigHub));
    }

    function test_rescueTokens_ERC20() public {
        uint amount = 1000;
        erc20.mint(address(testedContract), amount);
        assertEq(erc20.balanceOf(address(testedContract)), amount);

        vm.prank(owner);
        vm.expectEmit(address(testedContract));
        emit BaseManaged.TokensRescued(address(erc20), amount);
        testedContract.rescueTokens(address(erc20), amount, false);

        assertEq(erc20.balanceOf(owner), amount);
        assertEq(erc20.balanceOf(address(testedContract)), 0);
    }

    function test_rescueTokens_ERC721() public {
        uint id = 1000;
        erc721.mint(address(testedContract), id);
        assertEq(erc721.ownerOf(id), address(testedContract));

        vm.prank(owner);
        vm.expectEmit(address(testedContract));
        emit BaseManaged.TokensRescued(address(erc721), id);
        testedContract.rescueTokens(address(erc721), id, true);

        assertEq(erc721.ownerOf(id), owner);
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
        vm.expectRevert("invalid ConfigHub");
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
        testedContract.rescueTokens(address(0), 0, true);
    }

    function test_revert_pauseByGuardian_notGuardian() public {
        vm.prank(user1);
        vm.expectRevert("not guardian");
        testedContract.pauseByGuardian();

        vm.prank(owner);
        configHub.setPauseGuardian(user1, true);
        vm.prank(user1);
        testedContract.pauseByGuardian();
        assertTrue(testedContract.paused());
    }

    function test_revert_pauseByGuardian_ownerRenounced() public {
        vm.prank(owner);
        configHub.setPauseGuardian(guardian, true);

        vm.prank(owner);
        testedContract.renounceOwnership();

        vm.prank(guardian);
        vm.expectRevert("owner renounced");
        testedContract.pauseByGuardian();
    }

    function test_revert_guardian_unpause() public {
        vm.prank(owner);
        configHub.setPauseGuardian(guardian, true);

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
contract TestableBaseManaged is BaseManaged {
    constructor(address _initialOwner, ConfigHub _configHub) BaseManaged(_initialOwner) {
        _setConfigHub(_configHub);
    }
}

// the tests for the mock contract
contract BaseManagedMockTest is BaseManagedTestBase {
    function setupTestedContract() internal override {
        testedContract = new TestableBaseManaged(owner, configHub);
    }

    function test_revert_constructor_invalidConfigHub() public {
        vm.expectRevert(new bytes(0));
        new TestableBaseManaged(owner, ConfigHub(address(0)));

        ConfigHub badHub = ConfigHub(address(new BadConfigHub1()));
        vm.expectRevert();
        new TestableBaseManaged(owner, badHub);

        badHub = ConfigHub(address(new BadConfigHub2()));
        vm.expectRevert("invalid ConfigHub");
        new TestableBaseManaged(owner, badHub);
    }
}

contract ProviderNFTManagedTest is BaseManagedTestBase {
    function setupTestedContract() internal override {
        testedContract =
            new CollarProviderNFT(owner, configHub, erc20, erc20, address(0), "ProviderNFT", "ProviderNFT");
    }
}

contract EscrowSupplierNFTManagedTest is BaseManagedTestBase {
    function setupTestedContract() internal override {
        testedContract = new EscrowSupplierNFT(owner, configHub, erc20, "ProviderNFT", "ProviderNFT");
    }
}

contract TakerNFTManagedTest is BaseManagedTestBase {
    function setupTestedContract() internal virtual override {
        MockChainlinkFeed mockCLFeed = new MockChainlinkFeed(18, "TestFeed");
        ChainlinkOracle oracle = new ChainlinkOracle(
            address(erc20), address(erc20), address(mockCLFeed), "TestFeed", 60, address(0)
        );
        // taker checks price on construction
        mockCLFeed.setLatestAnswer(1, 0);
        testedContract =
            new CollarTakerNFT(owner, configHub, erc20, erc20, oracle, "CollarTakerNFT", "BRWTST");
    }
}

contract LoansManagedTest is TakerNFTManagedTest {
    function setupTestedContract() internal override {
        super.setupTestedContract();
        // take the taker contract setup by the super
        CollarTakerNFT takerNFT = CollarTakerNFT(address(testedContract));
        testedContract = new LoansNFT(owner, takerNFT, "", "");
    }
}

contract RollsManagedTest is TakerNFTManagedTest {
    function setupTestedContract() internal override {
        super.setupTestedContract();
        // take the taker contract setup by the super
        CollarTakerNFT takerNFT = CollarTakerNFT(address(testedContract));
        testedContract = new Rolls(owner, takerNFT);
    }
}
