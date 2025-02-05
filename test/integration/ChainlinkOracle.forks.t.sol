// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { ChainlinkOracle, IERC20Metadata, IChainlinkFeedLike } from "../../src/ChainlinkOracle.sol";
import { CollarOwnedERC20 } from "../utils/CollarOwnedERC20.sol";
import { Const } from "../../script/utils/Const.sol";

contract ChainlinkOracle_ArbiMain_WETHUSDC_ForkTest is Test {
    ChainlinkOracle public oracle;

    address constant VIRTUAL_ASSET = Const.VIRTUAL_ASSET;

    uint sequencerGracePeriod = 3600;
    uint expectedSequencerStartedAt;

    // setup for particular test class
    address baseToken;
    address quoteToken;
    address sequencerFeed;
    bool sequencerFeedExists;
    address priceFeed;
    string description;
    uint maxStaleness;

    // test values
    int expectedAnswer;
    uint expectedCurPrice;
    uint expectedInversePrice;

    function setUp() public virtual {
        _startFork();
        _config();
        _setUp();
        oracle =
            new ChainlinkOracle(baseToken, quoteToken, priceFeed, description, maxStaleness, sequencerFeed);
    }

    function _startFork() internal virtual {
        vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_RPC"), 242_273_401);
    }

    function _config() internal virtual {
        baseToken = Const.ArbiMain_WETH;
        quoteToken = Const.ArbiMain_USDC;

        sequencerFeedExists = true;
        sequencerFeed = Const.ArbiMain_SeqFeed;
        expectedSequencerStartedAt = 1_713_187_535;

        priceFeed = Const.ArbiMain_CLFeedETH_USD;
        description = "ETH / USD";
        maxStaleness = 1 days + 1 minutes; // some grace for congestion

        expectedAnswer = 271_363_750_525; // 2713 in 8 decimals
        expectedCurPrice = 2_713_637_505; // 2713 USDC per 1 ETH
        expectedInversePrice = 368_509_057_700_347; // 1e8 * 1e18 / 2_713_637_50525
    }

    function _setUp() internal virtual { }

    function expectedUnitAmount(address asset) internal view returns (uint) {
        return 10 ** ((asset == VIRTUAL_ASSET ? 18 : IERC20Metadata(asset).decimals()));
    }

    // effects tests

    function test_constructor() public {
        oracle =
            new ChainlinkOracle(baseToken, quoteToken, priceFeed, description, maxStaleness, sequencerFeed);
        assertEq(oracle.VERSION(), "0.2.0");
        assertEq(oracle.VIRTUAL_ASSET(), VIRTUAL_ASSET);
        assertEq(oracle.baseToken(), baseToken);
        assertEq(oracle.quoteToken(), quoteToken);
        assertEq(oracle.baseUnitAmount(), expectedUnitAmount(baseToken));
        assertEq(oracle.quoteUnitAmount(), expectedUnitAmount(quoteToken));
        assertEq(oracle.feedUnitAmount(), 10 ** IChainlinkFeedLike(priceFeed).decimals());
        assertEq(oracle.maxStaleness(), maxStaleness);
        assertEq(oracle.MIN_SEQUENCER_UPTIME(), sequencerGracePeriod);
        assertEq(address(oracle.priceFeed()), address(priceFeed));
        assertEq(address(oracle.sequencerChainlinkFeed()), sequencerFeed);

        if (sequencerFeedExists) assertTrue(oracle.sequencerLiveFor(sequencerGracePeriod));
    }

    function test_sequencerFeed() public {
        if (sequencerFeedExists) {
            assertTrue(oracle.sequencerLiveFor(0));
            assertTrue(oracle.sequencerLiveFor(sequencerGracePeriod));
            assertTrue(oracle.sequencerLiveFor(100 days));

            assertNotEq(address(oracle.sequencerChainlinkFeed()), address(0));
            // check feed
            (, int answer, uint startedAt,,) = oracle.sequencerChainlinkFeed().latestRoundData();
            assertEq(answer, 0);
            assertEq(startedAt, expectedSequencerStartedAt);

            // check view
            assertTrue(oracle.sequencerLiveFor(block.timestamp - expectedSequencerStartedAt));
            assertFalse(oracle.sequencerLiveFor(block.timestamp - expectedSequencerStartedAt + 1));
            assertFalse(oracle.sequencerLiveFor(block.timestamp - expectedSequencerStartedAt + 100 days));

            // price works
            uint price = oracle.currentPrice();
            assertNotEq(price, 0);
        } else {
            assertEq(address(oracle.sequencerChainlinkFeed()), address(0));

            vm.expectRevert("sequencer uptime feed unset");
            oracle.sequencerLiveFor(0);
        }
    }

    function test_answer() public view {
        (, int answer,,,) = oracle.priceFeed().latestRoundData();
        assertEq(answer, expectedAnswer);
    }

    function test_currentPrice() public view {
        assertEq(oracle.currentPrice(), expectedCurPrice);
    }

    function test_inversePrice() public view {
        assertEq(oracle.inversePrice(), expectedInversePrice);
    }
}

contract ChainlinkOracle_ArbiMain_WETHUSD_ForkTest is ChainlinkOracle_ArbiMain_WETHUSDC_ForkTest {
    function _setUp() internal virtual override {
        super._setUp();
        quoteToken = VIRTUAL_ASSET;
    }

    function _config() internal virtual override {
        super._config();
        // 18 decimals quote token instead of 6 now
        // more decimal places conserve the 2 truncated last decimals from the feed
        expectedCurPrice = 2_713_637_505_250_000_000_000;
        // expectedInversePrice is the same since output (base) token units didn't change
    }
}

contract ChainlinkOracle_ArbiMain_NewTokens_ForkTest is ChainlinkOracle_ArbiMain_WETHUSDC_ForkTest {
    function _setUp() internal virtual override {
        super._setUp();
        /// the new tokens are using the existing feed
        baseToken = address(new CollarOwnedERC20(address(this), "testETH", "testETH", 18));
        quoteToken = address(new CollarOwnedERC20(address(this), "testUSD", "testUSD", 18));
    }

    function _config() internal virtual override {
        super._config();
        // 18 decimals quote token instead of 6 now
        // more decimal places conserve the 2 truncated last decimals from the feed
        expectedCurPrice = 2_713_637_505_250_000_000_000;
        // expectedInversePrice is the same since output (base) token units didn't change
    }
}

contract ChainlinkOracle_ArbiSepolia_WBTCUSDC_ForkTest is ChainlinkOracle_ArbiMain_WETHUSDC_ForkTest {
    function _startFork() internal override {
        vm.createSelectFork(vm.envString("ARBITRUM_SEPOLIA_RPC"), 72_779_252);
    }

    function _config() internal virtual override {
        super._config();
        baseToken = 0x0d64F70fAd5897d752c6e9e9a80ac3C978BF6897; // WBTC arbi-sep
        quoteToken = 0xbDCc1D2ADE76E4A02539674D6D03E4bf571Da712; // USDC arbi-sep

        sequencerFeedExists = false;
        sequencerFeed = address(0);

        priceFeed = 0x56a43EB56Da12C0dc1D972ACb089c06a5dEF8e69;
        description = "BTC / USD";
        maxStaleness = 2 minutes + 10; // some grace for congestion

        // price is for 1e8 WBTC in USDC (because WBTC is 8 decimals)
        expectedAnswer = 5_939_999_000_000;
        expectedCurPrice = 59_399_990_000; // 59000 * 1e6 (USDC decimals)
        expectedInversePrice = 1683; // 1e8 * 1e8 / 5_939_999_000_000
    }
}

contract ChainlinkOracle_ArbiSepolia_BTCUSDC_ForkTest is ChainlinkOracle_ArbiSepolia_WBTCUSDC_ForkTest {
    function _setUp() internal virtual override {
        super._setUp();
        baseToken = VIRTUAL_ASSET;
    }

    function _config() internal virtual override {
        super._config();
        // 18 decimals base token instead of 8 now
        // more decimal places conserve the truncated last decimals from the feed
        expectedInversePrice = 16_835_019_669_195; // 1e6 * 1e18 / 59_399_990_000
    }
}

contract ChainlinkOracle_ArbiSepolia_BTCUSD_ForkTest is ChainlinkOracle_ArbiSepolia_BTCUSDC_ForkTest {
    function _setUp() internal virtual override {
        super._setUp();
        baseToken = VIRTUAL_ASSET;
        quoteToken = VIRTUAL_ASSET;
    }

    function _config() internal virtual override {
        super._config();
        // 18 decimals base and quote tokens instead of 8 now
        // more decimal places conserve the truncated last decimals from the feed
        expectedCurPrice = 59_399_990_000_000_000_000_000; // 59_399_990_000 * 1e18 / 1e8
    }
}

contract ChainlinkOracle_ArbiSepolia_NewTokens_ForkTest is ChainlinkOracle_ArbiMain_NewTokens_ForkTest {
    function _startFork() internal override {
        vm.createSelectFork(vm.envString("ARBITRUM_SEPOLIA_RPC"), 72_779_252);
    }

    function _setUp() internal virtual override {
        super._setUp();
        /// the new tokens are using the existing feed
        baseToken = address(new CollarOwnedERC20(address(this), "testBTC", "testBTC", 18));
        quoteToken = address(new CollarOwnedERC20(address(this), "testUSD", "testUSD", 18));
    }

    function _config() internal override {
        super._config();

        priceFeed = 0x56a43EB56Da12C0dc1D972ACb089c06a5dEF8e69;
        description = "BTC / USD";
        maxStaleness = 2 minutes + 10; // some grace for congestion

        sequencerFeedExists = false;
        sequencerFeed = address(0);

        // price is for 1e8 WBTC in 1e18 testUSD (because WBTC is 8 decimals)
        expectedAnswer = 5_939_999_000_000;
        expectedCurPrice = 59_399_990_000_000_000_000_000; // 59000 * 1e18
        expectedInversePrice = 16_835_019_669_195; // 1e18 * 1e18 / 59_399_990_000_000_000_000_000
    }
}

contract ChainlinkOracle_OPBaseMain_WETHUSDC_ForkTest is ChainlinkOracle_ArbiMain_WETHUSDC_ForkTest {
    function _startFork() internal override {
        vm.createSelectFork(vm.envString("OPBASE_MAINNET_RPC"), 25_666_192);
    }

    function _config() internal virtual override {
        super._config();
        baseToken = Const.OPBaseMain_WETH;
        quoteToken = Const.OPBaseMain_USDC;

        sequencerFeed = Const.OPBaseMain_SeqFeed;
        expectedSequencerStartedAt = 1_727_286_839;

        priceFeed = Const.OPBaseMain_CLFeedETH_USD;

        expectedAnswer = 311_621_000_000; // 3116 in 8 decimals
        expectedCurPrice = 3_116_210_000; // 3116 USDC per 1 ETH
        expectedInversePrice = 320_902_634_931_535; // 1e8 * 1e18 / 311_621_000_000
    }
}

contract ChainlinkOracle_OPBaseMain_CBBTCUSDC_ForkTest is ChainlinkOracle_OPBaseMain_WETHUSDC_ForkTest {
    function _config() internal virtual override {
        super._config();
        baseToken = Const.OPBaseMain_cbBTC;
        priceFeed = Const.OPBaseMain_CLFeedCBBTC_USD;
        description = "cbBTC / USD";

        expectedAnswer = 10_190_410_180_039; // 8 decimals
        expectedCurPrice = 101_904_101_800; // 6 decimals
        expectedInversePrice = 981; // 1e8 * 1e8 / 10_190_410_180_039
    }
}

contract ChainlinkOracle_OPBaseSep_WETHUSDC_ForkTest is ChainlinkOracle_ArbiMain_WETHUSDC_ForkTest {
    function _startFork() internal override {
        vm.createSelectFork(vm.envString("OPBASE_SEPOLIA_RPC"), 21_176_690);
    }

    function _config() internal virtual override {
        super._config();
        baseToken = Const.OPBaseSep_WETH;
        quoteToken = Const.OPBaseSep_USDC;

        sequencerFeedExists = false;
        sequencerFeed = address(0);

        priceFeed = Const.OPBaseSep_CLFeedETH_USD;

        expectedAnswer = 311_485_030_000; // 3114 in 8 decimals
        expectedCurPrice = 3_114_850_300_000_000_000_000; // 3114 18 decimals USDC per 1 ETH
        expectedInversePrice = 321_042_715_921_211; // 1e8 * 1e18 / 311_485_030_000
    }
}
