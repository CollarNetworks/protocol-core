// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockOracleUniV3TWAP } from "../utils/MockOracleUniV3TWAP.sol";

import { OracleUniV3TWAP } from "../../src/OracleUniV3TWAP.sol";
import { ConfigHub } from "../../src/ConfigHub.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { CollarProviderNFT } from "../../src/CollarProviderNFT.sol";
import { Rolls } from "../../src/Rolls.sol";

contract BaseAssetPairTestSetup is Test {
    TestERC20 cashAsset;
    TestERC20 underlying;
    ConfigHub configHub;
    MockOracleUniV3TWAP mockOracle;
    CollarTakerNFT takerNFT;
    CollarProviderNFT providerNFT;
    CollarProviderNFT providerNFT2;
    Rolls rolls;

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address provider = makeAddr("provider");
    address supplier = makeAddr("supplier");
    address keeper = makeAddr("keeper");
    address protocolFeeRecipient = makeAddr("feeRecipient");

    uint constant BIPS_100PCT = 10_000;

    uint ltv = 9000;
    uint duration = 300;
    uint callStrikePercent = 12_000;
    uint protocolFeeAPR = 100;

    uint underlyingAmount = 1 ether;
    uint largeAmount = 100_000 ether;
    uint twapPrice = 1000 ether;
    uint swapCashAmount = (underlyingAmount * twapPrice / 1e18);

    int rollFee = 1 ether;

    function setUp() public virtual {
        deployContracts();
        configureContracts();
        updatePrice();
        mintAssets();
    }

    function deployContracts() internal {
        cashAsset = new TestERC20("TestCash", "TestCash");
        underlying = new TestERC20("TestCollat", "TestCollat");
        vm.label(address(cashAsset), "TestCash");
        vm.label(address(underlying), "TestCollat");

        configHub = new ConfigHub(owner);
        vm.label(address(configHub), "ConfigHub");

        // asset pair contracts
        mockOracle = new MockOracleUniV3TWAP(address(underlying), address(cashAsset));
        takerNFT = new CollarTakerNFT(
            owner, configHub, cashAsset, underlying, mockOracle, "CollarTakerNFT", "TKRNFT"
        );
        providerNFT = new CollarProviderNFT(
            owner, configHub, cashAsset, underlying, address(takerNFT), "ProviderNFT", "PRVNFT"
        );
        // this is to avoid having the paired IDs being equal
        providerNFT2 = new CollarProviderNFT(
            owner, configHub, cashAsset, underlying, address(takerNFT), "ProviderNFT-2", "PRVNFT-2"
        );
        vm.label(address(mockOracle), "MockOracleUniV3TWAP");
        vm.label(address(takerNFT), "CollarTakerNFT");
        vm.label(address(providerNFT), "CollarProviderNFT");

        // asset pair periphery
        rolls = new Rolls(owner, takerNFT);
        vm.label(address(rolls), "Rolls");
    }

    function configureContracts() public {
        startHoax(owner);

        // assets
        configHub.setCashAssetSupport(address(cashAsset), true);
        configHub.setUnderlyingSupport(address(underlying), true);
        // terms
        configHub.setLTVRange(ltv, ltv);
        configHub.setCollarDurationRange(duration, duration);
        // contracts auth
        configHub.setCanOpen(address(takerNFT), true);
        configHub.setCanOpen(address(providerNFT), true);
        configHub.setCanOpen(address(providerNFT2), true);
        // fees
        configHub.setProtocolFeeParams(protocolFeeAPR, protocolFeeRecipient);

        vm.stopPrank();
    }

    function updatePrice() public {
        mockOracle.setHistoricalAssetPrice(block.timestamp, twapPrice);
    }

    function updatePrice(uint price) public {
        mockOracle.setHistoricalAssetPrice(block.timestamp, price);
    }

    function mintAssets() public {
        underlying.mint(user1, underlyingAmount * 10);
        cashAsset.mint(user1, swapCashAmount * 10);
        cashAsset.mint(provider, largeAmount * 10);
        underlying.mint(supplier, largeAmount * 10);
    }

    function expectRevertERC721Nonexistent(uint id) internal {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, id));
    }
}
