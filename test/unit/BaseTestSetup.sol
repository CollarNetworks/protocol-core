// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { TestERC20 } from "../utils/TestERC20.sol";
import { MockOracleUniV3TWAP } from "../utils/MockOracleUniV3TWAP.sol";

import { Loans } from "../../src/Loans.sol";
import { OracleUniV3TWAP } from "../../src/OracleUniV3TWAP.sol";
import { ConfigHub } from "../../src/ConfigHub.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { ProviderPositionNFT } from "../../src/ProviderPositionNFT.sol";
import { Rolls } from "../../src/Rolls.sol";

contract BaseTestSetup is Test {
    TestERC20 cashAsset;
    TestERC20 collateralAsset;
    ConfigHub configHub;
    MockOracleUniV3TWAP mockOracle;
    CollarTakerNFT takerNFT;
    ProviderPositionNFT providerNFT;
    ProviderPositionNFT providerNFT2;
    Loans loans;
    Rolls rolls;

    address owner = makeAddr("owner");
    address user1 = makeAddr("user1");
    address provider = makeAddr("provider");
    address keeper = makeAddr("keeper");

    uint constant BIPS_100PCT = 10_000;

    uint ltv = 9000;
    uint duration = 300;
    uint callStrikeDeviation = 12_000;

    uint collateralAmount = 1 ether;
    uint largeAmount = 100_000 ether;
    uint twapPrice = 1000 ether;
    uint swapCashAmount = (collateralAmount * twapPrice / 1e18);

    int rollFee = 1 ether;

    function setUp() public virtual {
        deployContracts();
        configureContracts();
        updatePrice();
        mintAssets();
    }

    function deployContracts() internal {
        cashAsset = new TestERC20("TestCash", "TestCash");
        collateralAsset = new TestERC20("TestCollat", "TestCollat");
        vm.label(address(cashAsset), "TestCash");
        vm.label(address(collateralAsset), "TestCollat");

        configHub = new ConfigHub(owner);
        vm.label(address(configHub), "ConfigHub");

        // asset pair contracts
        mockOracle = new MockOracleUniV3TWAP(address(collateralAsset), address(cashAsset));
        takerNFT = new CollarTakerNFT(
            owner, configHub, cashAsset, collateralAsset, mockOracle, "CollarTakerNFT", "TKRNFT"
        );
        providerNFT = new ProviderPositionNFT(
            owner, configHub, cashAsset, collateralAsset, address(takerNFT), "ProviderNFT", "PRVNFT"
        );
        // this is to avoid having the paired IDs being equal
        providerNFT2 = new ProviderPositionNFT(
            owner, configHub, cashAsset, collateralAsset, address(takerNFT), "ProviderNFT-2", "PRVNFT-2"
        );
        vm.label(address(mockOracle), "MockOracleUniV3TWAP");
        vm.label(address(takerNFT), "CollarTakerNFT");
        vm.label(address(providerNFT), "ProviderPositionNFT");

        // asset pair periphery
        rolls = new Rolls(owner, takerNFT);
        loans = new Loans(owner, takerNFT);
        vm.label(address(rolls), "Rolls");
        vm.label(address(loans), "Loans");
    }

    function configureContracts() public {
        startHoax(owner);

        configHub.setCashAssetSupport(address(cashAsset), true);
        configHub.setCollateralAssetSupport(address(collateralAsset), true);
        configHub.setLTVRange(ltv, ltv);
        configHub.setCollarDurationRange(duration, duration);
        configHub.setCollarTakerContractAuth(address(takerNFT), true);
        configHub.setProviderContractAuth(address(providerNFT), true);
        configHub.setProviderContractAuth(address(providerNFT2), true);

        loans.setRollsContract(rolls);
        vm.stopPrank();
    }

    function updatePrice() public {
        mockOracle.setHistoricalAssetPrice(block.timestamp, twapPrice);
    }

    function updatePrice(uint price) public {
        mockOracle.setHistoricalAssetPrice(block.timestamp, price);
    }

    function mintAssets() public {
        collateralAsset.mint(user1, collateralAmount * 10);
        cashAsset.mint(user1, swapCashAmount * 10);
        cashAsset.mint(provider, largeAmount * 10);
    }
}