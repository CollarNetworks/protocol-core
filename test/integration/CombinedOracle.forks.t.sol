// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { ChainlinkOracle, IERC20Metadata, IChainlinkFeedLike } from "../../src/ChainlinkOracle.sol";
import { CombinedOracle } from "../../src/CombinedOracle.sol";
import { CollarOwnedERC20 } from "../utils/CollarOwnedERC20.sol";

contract CombinedOracle_ArbiMain_WETHUSDC_ForkTest is Test {
    address constant VIRTUAL_ASSET = address(type(uint160).max); // 0xff..ff

    CombinedOracle public comboOracle;
    ChainlinkOracle public oracle_1;
    ChainlinkOracle public oracle_2;

    uint sequencerGracePeriod = 3600;
    address sequencerFeed;
    bool sequencerFeedExists;

    // setup for particular test class
    address comboBaseToken;
    address comboQuoteToken;
    bool invert1;
    bool invert2;
    address baseToken1;
    address baseToken2;
    address quoteToken1;
    address quoteToken2;
    address priceFeed1;
    address priceFeed2;
    string description1;
    string description2;
    uint maxStaleness1;
    uint maxStaleness2;

    // test values
    int expectedAnswer1;
    int expectedAnswer2;
    uint expectedCurPrice1;
    uint expectedCurPrice2;
    uint expectedComboPrice;
    uint expectedComboInverse;

    function setUp() public virtual {
        _startFork();
        _config();
        _setUp();
        oracle_1 = new ChainlinkOracle(
            baseToken1, quoteToken1, priceFeed1, description1, maxStaleness1, sequencerFeed
        );
        oracle_2 = new ChainlinkOracle(
            baseToken2, quoteToken2, priceFeed2, description2, maxStaleness2, sequencerFeed
        );
        comboOracle = new CombinedOracle(
            comboBaseToken, comboQuoteToken, address(oracle_1), invert1, address(oracle_2), invert2
        );
    }

    function _startFork() internal virtual {
        vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_RPC"), 242_273_401);
    }

    function _config() internal virtual {
        sequencerFeedExists = true;
        sequencerFeed = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;

        baseToken1 = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        quoteToken1 = VIRTUAL_ASSET; // USD_18
        priceFeed1 = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
        description1 = "ETH / USD";
        maxStaleness1 = 1 days + 1 minutes; // some grace for congestion

        baseToken2 = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC
        quoteToken2 = VIRTUAL_ASSET; // USD_18
        priceFeed2 = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
        description2 = "USDC / USD";
        maxStaleness2 = 1 days + 1 minutes; // some grace for congestion

        comboBaseToken = baseToken1;
        comboQuoteToken = baseToken2;
        invert1 = false;
        invert2 = true;

        expectedAnswer1 = 271_363_750_525; // 2713 in 8 decimals
        expectedCurPrice1 = 2_713_637_505_250_000_000_000; // 2713 USD_18, upscaled from 8 decimals

        expectedAnswer2 = 99_992_001; // 1e8
        expectedCurPrice2 = 999_920_010_000_000_000; // 1 USD_18, upscaled from 8 decimals

        expectedComboPrice = 2_713_851_882; // 2713 in 6 decimals
        // 99992001 * 1e18 / 271_363_750_525 = 368_479_580_660_822, 1 wei precision loss
        expectedComboInverse = 368_479_580_660_821;
    }

    function _setUp() internal virtual { }

    function expectedUnitAmount(address asset) internal view returns (uint) {
        return 10 ** ((asset == VIRTUAL_ASSET ? 18 : IERC20Metadata(asset).decimals()));
    }

    // effects tests

    function test_constructor() public {
        comboOracle = new CombinedOracle(
            comboBaseToken, comboQuoteToken, address(oracle_1), invert1, address(oracle_2), invert2
        );

        // BaseTakerOracle
        assertEq(comboOracle.VIRTUAL_ASSET(), VIRTUAL_ASSET);
        assertEq(comboOracle.baseToken(), baseToken1);
        assertEq(comboOracle.quoteToken(), baseToken2);
        assertEq(comboOracle.baseUnitAmount(), expectedUnitAmount(baseToken1));
        assertEq(comboOracle.quoteUnitAmount(), expectedUnitAmount(baseToken2));
        assertEq(address(comboOracle.sequencerChainlinkFeed()), address(0));
        // CombinedOracle
        assertEq(comboOracle.VERSION(), "0.2.0");
        assertEq(address(comboOracle.oracle_1()), address(oracle_1));
        assertEq(address(comboOracle.oracle_2()), address(oracle_2));
        assertEq(comboOracle.invert_1(), invert1);
        assertEq(comboOracle.invert_2(), invert2);
    }

    function test_sequencerFeed() public {
        vm.expectRevert("sequencer uptime feed unset");
        comboOracle.sequencerLiveFor(0);
        assertEq(address(comboOracle.sequencerChainlinkFeed()), address(0));
        assertNotEq(comboOracle.currentPrice(), 0);

        if (sequencerFeedExists) {
            assertTrue(oracle_1.sequencerLiveFor(0));
            assertTrue(oracle_2.sequencerLiveFor(0));
            assertTrue(oracle_1.sequencerLiveFor(sequencerGracePeriod));
            assertTrue(oracle_2.sequencerLiveFor(sequencerGracePeriod));

            assertNotEq(address(oracle_1.sequencerChainlinkFeed()), address(0));
            assertNotEq(address(oracle_2.sequencerChainlinkFeed()), address(0));

            // check feed
            (, int answer, uint startedAt,,) = oracle_1.sequencerChainlinkFeed().latestRoundData();
            assertEq(answer, 0);
            uint32 expectedStartedAt = 1_713_187_535;
            assertEq(startedAt, expectedStartedAt);

            // check view
            assertTrue(oracle_1.sequencerLiveFor(block.timestamp - expectedStartedAt));
            assertFalse(oracle_1.sequencerLiveFor(block.timestamp - expectedStartedAt + 1));

            // price works
            assertNotEq(oracle_1.currentPrice(), 0);
            assertNotEq(oracle_2.currentPrice(), 0);
        }
    }

    function test_oracle_1() public view {
        (, int answer1,,,) = oracle_1.priceFeed().latestRoundData();
        assertEq(answer1, expectedAnswer1, "expectedAnswer1");
        assertEq(oracle_1.currentPrice(), expectedCurPrice1, "expectedCurPrice1");
    }

    function test_oracle_2() public view {
        (, int answer2,,,) = oracle_2.priceFeed().latestRoundData();
        assertEq(answer2, expectedAnswer2, "expectedAnswer2");
        assertEq(oracle_2.currentPrice(), expectedCurPrice2, "expectedCurPrice2");
    }

    function test_currentPrice() public view {
        assertEq(comboOracle.currentPrice(), expectedComboPrice, "expectedComboPrice");
    }

    function test_inversePrice() public view {
        assertEq(comboOracle.inversePrice(), expectedComboInverse, "expectedComboInverse");
    }
}

contract CombinedOracle_ArbiMain_USDCWETH_ForkTest is CombinedOracle_ArbiMain_WETHUSDC_ForkTest {
    function setUp() public virtual override {
        super.setUp();
        comboOracle = new CombinedOracle(
            comboQuoteToken, comboBaseToken, address(oracle_2), invert1, address(oracle_1), invert2
        );
    }

    function _config() internal virtual override {
        super._config();

        // 99992001 * 1e18 / 271_363_750_525 = 368_479_580_660_822, 1 wei precision loss
        expectedComboPrice = 368_479_580_660_821;
        expectedComboInverse = 2_713_851_882; // 2713 in 6 decimals
    }
}

contract CombinedOracle_ArbiSepolia_WBTCUSDC_ForkTest is CombinedOracle_ArbiMain_WETHUSDC_ForkTest {
    function _startFork() internal override {
        vm.createSelectFork(vm.envString("ARBITRUM_SEPOLIA_RPC"), 72_779_252);
    }

    function _config() internal virtual override {
        super._config();
        sequencerFeedExists = false;
        sequencerFeed = address(0);

        baseToken1 = 0x0d64F70fAd5897d752c6e9e9a80ac3C978BF6897; // WBTC
        quoteToken1 = VIRTUAL_ASSET; // USD_18
        priceFeed1 = 0x56a43EB56Da12C0dc1D972ACb089c06a5dEF8e69;
        description1 = "BTC / USD";
        maxStaleness1 = 2 minutes + 10; // some grace for congestion

        baseToken2 = 0xbDCc1D2ADE76E4A02539674D6D03E4bf571Da712; // USDC
        quoteToken2 = VIRTUAL_ASSET; // USD_18
        priceFeed2 = 0x0153002d20B96532C639313c2d54c3dA09109309;
        description2 = "USDC / USD";
        maxStaleness2 = 1 days + 1 minutes; // some grace for congestion

        comboBaseToken = baseToken1;
        comboQuoteToken = baseToken2;
        invert1 = false;
        invert2 = true;

        expectedAnswer1 = 5_939_999_000_000; // 8 decimals
        expectedCurPrice1 = 59_399_990_000_000_000_000_000; // 59000 * 1e18

        expectedAnswer2 = 100_003_280; // 1e8
        expectedCurPrice2 = 1_000_032_800_000_000_000; // 1 USD_18, upscaled from 8 decimals

        expectedComboPrice = 59_398_029_800; // 59000 * 1e6 (USDC decimals)
        expectedComboInverse = 1683;
    }
}
