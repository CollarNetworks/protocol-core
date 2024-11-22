// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { IERC721Errors } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IERC20Errors } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { TestERC20 } from "../utils/TestERC20.sol";
import { MockChainlinkFeed } from "../utils/MockChainlinkFeed.sol";

import { ConfigHub } from "../../src/ConfigHub.sol";
import { CollarTakerNFT } from "../../src/CollarTakerNFT.sol";
import { CollarProviderNFT } from "../../src/CollarProviderNFT.sol";
import { Rolls } from "../../src/Rolls.sol";
import { ChainlinkOracle, BaseTakerOracle } from "../../src/ChainlinkOracle.sol";

contract BaseAssetPairTestSetup is Test {
    TestERC20 cashAsset;
    TestERC20 underlying;
    ConfigHub configHub;
    MockChainlinkFeed mockCLFeed;
    ChainlinkOracle chainlinkOracle;
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
    uint constant FEED_STALENESS = 1000;

    uint ltv = 9000;
    uint duration = 300;
    uint callStrikePercent = 12_000;
    uint protocolFeeAPR = 100;

    uint underlyingAmount = 1 ether;
    uint largeAmount = 100_000 ether;
    uint oraclePrice = 1000 ether;
    uint swapCashAmount = (underlyingAmount * oraclePrice / 1e18);

    int rollFee = 1 ether;

    function setUp() public virtual {
        deployContracts();
        configureContracts();
        updatePrice();
        mintAssets();
        mintDustToProtocolAddresses();
    }

    function deployContracts() internal {
        cashAsset = new TestERC20("TestCash", "TestCash");
        underlying = new TestERC20("TestCollat", "TestCollat");
        vm.label(address(cashAsset), "TestCash");
        vm.label(address(underlying), "TestCollat");

        configHub = new ConfigHub(owner);
        vm.label(address(configHub), "ConfigHub");

        // asset pair contracts
        mockCLFeed = new MockChainlinkFeed(18, "TestFeed");
        chainlinkOracle = createMockFeedOracle(address(underlying), address(cashAsset));

        // taker checks oracle price on construction
        updatePrice();
        takerNFT = new CollarTakerNFT(
            owner, configHub, cashAsset, underlying, chainlinkOracle, "CollarTakerNFT", "TKRNFT"
        );
        providerNFT = new CollarProviderNFT(
            owner, configHub, cashAsset, underlying, address(takerNFT), "ProviderNFT", "PRVNFT"
        );
        // this is to avoid having the paired IDs being equal
        providerNFT2 = new CollarProviderNFT(
            owner, configHub, cashAsset, underlying, address(takerNFT), "ProviderNFT-2", "PRVNFT-2"
        );
        vm.label(address(chainlinkOracle), "MockChainlinkOracle");
        vm.label(address(takerNFT), "CollarTakerNFT");
        vm.label(address(providerNFT), "CollarProviderNFT");

        // asset pair periphery
        rolls = new Rolls(owner, takerNFT);
        vm.label(address(rolls), "Rolls");
    }

    function createMockFeedOracle(address base, address quote) public returns (ChainlinkOracle) {
        return new ChainlinkOracle(base, quote, address(mockCLFeed), "TestFeed", FEED_STALENESS, address(0));
    }

    function configureContracts() public {
        startHoax(owner);

        // terms
        configHub.setLTVRange(ltv, ltv);
        configHub.setCollarDurationRange(duration, duration);
        // contracts auth
        configHub.setCanOpenPair(underlying, cashAsset, address(takerNFT), true);
        configHub.setCanOpenPair(underlying, cashAsset, address(providerNFT), true);
        configHub.setCanOpenPair(underlying, cashAsset, address(providerNFT2), true);
        // fees
        configHub.setProtocolFeeParams(protocolFeeAPR, protocolFeeRecipient);

        vm.stopPrank();
    }

    function setCanOpen(address target, bool enabled) internal {
        startHoax(owner);
        configHub.setCanOpenPair(underlying, cashAsset, target, enabled);
        vm.stopPrank();
    }

    function setCanOpenSingle(address target, bool enabled) internal {
        startHoax(owner);
        configHub.setCanOpenPair(underlying, configHub.ANY_ASSET(), target, enabled);
        vm.stopPrank();
    }

    function updatePrice() public {
        require(int(oraclePrice) > 0, "bad price");
        mockCLFeed.setLatestAnswer(int(oraclePrice), block.timestamp);
    }

    function updatePrice(uint price) public {
        require(int(price) > 0, "bad price");
        mockCLFeed.setLatestAnswer(int(price), block.timestamp);
    }

    function mintAssets() public {
        underlying.mint(user1, underlyingAmount * 10);
        cashAsset.mint(user1, swapCashAmount * 10);
        cashAsset.mint(provider, largeAmount * 10);
        underlying.mint(supplier, largeAmount * 10);
    }

    function mintDustToProtocolAddresses() public {
        // this both ensures balances aren't assumed to be 0, and reduces gas usage
        cashAsset.mint(address(takerNFT), 1);
        cashAsset.mint(address(providerNFT), 1);
        cashAsset.mint(address(providerNFT2), 1);
        cashAsset.mint(address(rolls), 1);
        cashAsset.mint(protocolFeeRecipient, 1);

        // mint NFTs to rolls, reduces gas usage, trips up assumptions about IDs
        dustPairedPositionNFTs(address(rolls));
    }

    // mint NFTs to reduce gas usage, and trip up assumptions about IDs
    function dustPairedPositionNFTs(address to) internal {
        startHoax(provider);
        cashAsset.approve(address(providerNFT), 2);
        // symmetric offer, offer is 2 because of protocol fee (rounded up)
        uint offerId = providerNFT.createOffer(BIPS_100PCT + (BIPS_100PCT - ltv), 2, ltv, duration, 0);
        cashAsset.approve(address(takerNFT), 1);
        // open the two positions
        (uint takerId, uint providerId) = takerNFT.openPairedPosition(1, providerNFT, offerId);
        // transfer the NFTs to the destination
        takerNFT.transferFrom(provider, to, takerId);
        providerNFT.transferFrom(provider, to, providerId);
    }

    function expectRevertERC721Nonexistent(uint id) internal {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, id));
    }

    function expectRevertERC20Allowance(address spender, uint allowance, uint needed) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, needed
            )
        );
    }
}
