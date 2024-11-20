// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { ChainlinkOracle, IERC20Metadata, IChainlinkFeedLike } from "../../src/ChainlinkOracle.sol";
import { CollarOwnedERC20 } from "../utils/CollarOwnedERC20.sol";

contract ChainlinkOracle_ArbiMain_USDCWETH_ForkTest is Test {
    ChainlinkOracle public oracle;

    uint sequencerGracePeriod = 3600;

    // setup for particular test class
    address baseToken;
    address quoteToken;
    address sequencerFeed;
    bool sequencerFeedExists;
    address priceFeed;
    string description;
    uint maxStaleness;

    // test values
    uint expectedCurPrice;

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
        baseToken = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // WETH
        quoteToken = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831; // USDC

        sequencerFeedExists = true;
        sequencerFeed = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;

        priceFeed = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
        description = "ETH / USD";
        maxStaleness = 1 days + 1 minutes; // some grace for congestion

        expectedCurPrice = 2_713_637_505; // 2713 USDC per 1 ETH
    }

    function _setUp() internal virtual { }

    // effects tests

    function test_constructor() public {
        oracle =
            new ChainlinkOracle(baseToken, quoteToken, priceFeed, description, maxStaleness, sequencerFeed);
        assertEq(oracle.VERSION(), "0.2.0");
        assertEq(oracle.baseToken(), baseToken);
        assertEq(oracle.quoteToken(), quoteToken);
        assertEq(oracle.baseUnitAmount(), 10 ** IERC20Metadata(baseToken).decimals());
        assertEq(oracle.quoteUnitAmount(), 10 ** IERC20Metadata(quoteToken).decimals());
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
            uint32 expectedStartedAt = 1_713_187_535;
            assertEq(startedAt, expectedStartedAt);

            // check view
            assertTrue(oracle.sequencerLiveFor(block.timestamp - expectedStartedAt));
            assertFalse(oracle.sequencerLiveFor(block.timestamp - expectedStartedAt + 1));
            assertFalse(oracle.sequencerLiveFor(block.timestamp - expectedStartedAt + 100 days));

            // price works
            uint price = oracle.currentPrice();
            assertNotEq(price, 0);
        } else {
            assertEq(address(oracle.sequencerChainlinkFeed()), address(0));

            vm.expectRevert("sequencer uptime feed unset");
            oracle.sequencerLiveFor(0);
        }
    }

    function test_currentPrice() public view {
        assertEq(oracle.currentPrice(), expectedCurPrice);
    }
}

contract ChainlinkOracle_ArbiSepolia_USDCWBTC_ForkTest is ChainlinkOracle_ArbiMain_USDCWETH_ForkTest {
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
        expectedCurPrice = 59_399_990_000; // 59000 * 1e6 (USDC decimals)
    }
}

contract ChainlinkOracle_ArbiMain_NewTokens_ForkTest is ChainlinkOracle_ArbiMain_USDCWETH_ForkTest {
    function _setUp() internal virtual override {
        super._setUp();
        /// the new tokens are using the existing feed
        baseToken = address(new CollarOwnedERC20(address(this), "testETH", "testETH"));
        quoteToken = address(new CollarOwnedERC20(address(this), "testUSD", "testUSD"));
    }

    function _config() internal virtual override {
        super._config();
        // 18 decimals quote token instead of 6 now
        // more decimal places conserve the 2 truncated last decimals from the feed
        expectedCurPrice = 2_713_637_505_250_000_000_000;
    }
}

contract ChainlinkOracle_ArbiSepolia_NewPool_ForkTest is ChainlinkOracle_ArbiMain_NewTokens_ForkTest {
    function _startFork() internal override {
        vm.createSelectFork(vm.envString("ARBITRUM_SEPOLIA_RPC"), 72_779_252);
    }

    function _setUp() internal virtual override {
        super._setUp();
        /// the new tokens are using the existing feed
        baseToken = address(new CollarOwnedERC20(address(this), "testBTC", "testBTC"));
        quoteToken = address(new CollarOwnedERC20(address(this), "testUSD", "testUSD"));
    }

    function _config() internal override {
        super._config();

        priceFeed = 0x56a43EB56Da12C0dc1D972ACb089c06a5dEF8e69;
        description = "BTC / USD";
        maxStaleness = 2 minutes + 10; // some grace for congestion

        sequencerFeedExists = false;
        sequencerFeed = address(0);

        // price is for 1e8 WBTC in 1e18 USDC (because WBTC is 8 decimals)
        expectedCurPrice = 59_399_990_000_000_000_000_000; // 59000 * 1e18
    }
}
