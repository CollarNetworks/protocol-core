// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { TestERC20 } from "../utils/TestERC20.sol";
import { MockChainlinkFeed } from "../utils/MockChainlinkFeed.sol";

import { BaseManaged } from "../../src/base/BaseManaged.sol";
import { ConfigHub } from "../../src/ConfigHub.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { CollarProviderNFT } from "../../src/CollarProviderNFT.sol";
import { EscrowSupplierNFT } from "../../src/EscrowSupplierNFT.sol";
import { LoansNFT } from "../../src/LoansNFT.sol";
import { ChainlinkOracle } from "../../src/ChainlinkOracle.sol";

// base contract for other tests that will check this functionality
abstract contract BaseManagedTestBase is Test {
    ConfigHub configHub;

    BaseManaged testedContract;

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");

    function setUp() public virtual {
        configHub = new ConfigHub(owner);

        setupTestedContract();

        vm.label(address(configHub), "ConfigHub");
    }

    /// @dev this is virtual to be filled by inheriting test contracts
    function setupTestedContract() internal virtual;

    function test_constructor() public {
        setupTestedContract();
        assertEq(testedContract.configHubOwner(), owner);
        assertEq(address(testedContract.configHub()), address(configHub));
    }

    function test_setConfigHub() public {
        ConfigHub newConfigHub = new ConfigHub(owner);

        vm.prank(owner);
        vm.expectEmit(address(testedContract));
        emit BaseManaged.ConfigHubUpdated(configHub, newConfigHub);
        testedContract.setConfigHub(newConfigHub);

        assertEq(address(testedContract.configHub()), address(newConfigHub));
    }

    // reverts

    function test_revert_setConfigHub_invalidConfigHub() public {
        vm.startPrank(owner);

        vm.expectRevert(new bytes(0));
        testedContract.setConfigHub(ConfigHub(address(0)));

        ConfigHub badHub = ConfigHub(address(new BadConfigHub1()));
        vm.expectRevert(new bytes(0));
        testedContract.setConfigHub(badHub);

        badHub = ConfigHub(address(new BadConfigHub2(owner)));
        vm.expectRevert("invalid ConfigHub");
        testedContract.setConfigHub(badHub);
    }

    function test_revert_setConfigHub_invalidConfigHubOwner() public {
        vm.startPrank(owner);

        ConfigHub hubDifferentOwner = new ConfigHub(user1);
        vm.expectRevert("BaseManaged: new configHub owner mismatch");
        testedContract.setConfigHub(hubDifferentOwner);

        // has no owner view, so reverts when trying to get owner()
        vm.expectRevert(new bytes(0));
        testedContract.setConfigHub(ConfigHub(address(testedContract)));
    }

    function test_onlyConfigHubOwnerMethods() public {
        startHoax(user1);

        vm.expectRevert("BaseManaged: not configHub owner");
        testedContract.setConfigHub(configHub);
    }
}

contract BadConfigHub1 {
    fallback() external { }
}

contract BadConfigHub2 {
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function VERSION() external returns (string memory) { }
}

// mock of an inheriting contract (because base is abstract)
contract TestableBaseManaged is BaseManaged {
    constructor(ConfigHub _configHub) BaseManaged(_configHub) { }
}

// the tests for the mock contract
contract BaseManagedMockTest is BaseManagedTestBase {
    function setupTestedContract() internal override {
        testedContract = new TestableBaseManaged(configHub);
    }

    function test_revert_constructor_invalidConfigHub() public {
        vm.expectRevert(new bytes(0));
        new TestableBaseManaged(ConfigHub(address(0)));

        ConfigHub badHub = ConfigHub(address(new BadConfigHub1()));
        vm.expectRevert();
        new TestableBaseManaged(badHub);

        badHub = ConfigHub(address(new BadConfigHub2(owner)));
        vm.expectRevert("invalid ConfigHub");
        new TestableBaseManaged(badHub);
    }
}

contract ProviderNFTManagedTest is BaseManagedTestBase {
    function setupTestedContract() internal override {
        TestERC20 erc20 = new TestERC20("TestERC20_2", "TestERC20_2", 18);
        testedContract =
            new CollarProviderNFT(configHub, erc20, erc20, address(0), "ProviderNFT", "ProviderNFT");
    }
}

contract EscrowSupplierNFTManagedTest is BaseManagedTestBase {
    function setupTestedContract() internal override {
        TestERC20 erc20 = new TestERC20("TestERC20_2", "TestERC20_2", 18);
        testedContract = new EscrowSupplierNFT(configHub, erc20, "ProviderNFT", "ProviderNFT");
    }
}

contract TakerNFTManagedTest is BaseManagedTestBase {
    function setupTestedContract() internal virtual override {
        TestERC20 erc20 = new TestERC20("TestERC20_2", "TestERC20_2", 18);
        TestERC20 erc20_2 = new TestERC20("TestERC20_2", "TestERC20_2", 18);
        MockChainlinkFeed mockCLFeed = new MockChainlinkFeed(18, "TestFeed");
        ChainlinkOracle oracle = new ChainlinkOracle(
            address(erc20), address(erc20_2), address(mockCLFeed), "TestFeed", 60, address(0)
        );
        // taker checks price on construction
        mockCLFeed.setLatestAnswer(1, 0);
        testedContract = new CollarTakerNFT(configHub, erc20_2, erc20, oracle, "CollarTakerNFT", "BRWTST");
    }
}

contract LoansManagedTest is TakerNFTManagedTest {
    function setupTestedContract() internal override {
        super.setupTestedContract();
        // take the taker contract setup by the super
        CollarTakerNFT takerNFT = CollarTakerNFT(address(testedContract));
        testedContract = new LoansNFT(takerNFT, "", "");
    }
}
