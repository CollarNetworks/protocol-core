// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { Const } from "../../script/utils/Const.sol";
import { UniswapNewPoolHelper } from "../utils/UniswapNewPoolHelper.sol";
import { OracleUniV3TWAP } from "../utils/OracleUniV3TWAP.sol";

contract OracleUniV3TWAP_ArbiMain_USDCWETH_ForkTest is Test {
    OracleUniV3TWAP public oracle;

    address router = Const.ArbiMain_UniRouter;
    uint24 feeTier = 500;

    uint32 twapWindow = 300;

    // setup for particular test class
    address baseToken;
    address quoteToken;
    address pool;
    address sequencerFeed;
    bool sequencerFeedExists;

    // test values
    uint expectedCurPrice;
    uint expectedPriceTwapWindowAgo;
    uint16 expectedCardinality;

    // old factory, so reverts with require(, 'OLD') instead of custom error as in newer implementations
    // https://arbiscan.io/address/0xC6962004f452bE9203591991D15f6b388e09E8D0#code#F9#L226
    bytes revertBytesOLD = bytes("OLD");

    function setUp() public virtual {
        _startFork();
        _config();
        _setUp();
        oracle = new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow, router, sequencerFeed);
    }

    function _startFork() internal virtual {
        vm.createSelectFork(vm.envString("ARBITRUM_MAINNET_RPC"), 242_273_401);
    }

    function _config() internal virtual {
        baseToken = Const.ArbiMain_WETH;
        quoteToken = Const.ArbiMain_USDC;

        sequencerFeedExists = true;
        sequencerFeed = Const.ArbiMain_SeqFeed;

        pool = 0xC6962004f452bE9203591991D15f6b388e09E8D0;
        expectedCardinality = 8000;
        expectedCurPrice = 2_713_263_289; // 2713 USDC per 1 ETH
        expectedPriceTwapWindowAgo = 2_720_326_598;
    }

    function _setUp() internal virtual { }

    // effects tests

    function test_constructor() public {
        oracle = new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow, router, sequencerFeed);
        assertEq(oracle.VERSION(), "0.2.0");
        assertEq(oracle.MIN_TWAP_WINDOW(), 300);
        assertEq(oracle.baseToken(), baseToken);
        assertEq(oracle.quoteToken(), quoteToken);
        assertEq(oracle.feeTier(), feeTier);
        assertEq(oracle.twapWindow(), twapWindow);
        assertEq(address(oracle.pool()), pool);
        assertEq(address(oracle.sequencerChainlinkFeed()), sequencerFeed);
        if (sequencerFeedExists) assertTrue(oracle.sequencerLiveFor(twapWindow));
    }

    function test_sequencerFeed() public {
        if (sequencerFeedExists) {
            assertTrue(oracle.sequencerLiveFor(0));
            assertTrue(oracle.sequencerLiveFor(twapWindow));
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

            // very long twap window to check sequencer check causes reverts
            twapWindow = uint32(block.timestamp) - expectedStartedAt + 1;
            oracle = new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow, router, sequencerFeed);

            // reverts due to sequencer
            vm.expectRevert("sequencer uptime interrupted");
            oracle.currentPrice();

            skip(1);
            // doesn't revert due to sequencer, but due to not having data
            vm.expectRevert(bytes("OLD"));
            oracle.currentPrice();
        } else {
            assertEq(address(oracle.sequencerChainlinkFeed()), address(0));

            vm.expectRevert("sequencer uptime feed unset");
            oracle.sequencerLiveFor(0);
        }
    }

    function test_currentCardinality() public view {
        assertEq(oracle.currentCardinality(), expectedCardinality);
    }

    function test_currentPrice() public view {
        assertEq(oracle.currentPrice(), expectedCurPrice);
    }

    function test_increaseCardinality() public {
        uint16 toAdd = 100;
        oracle.increaseCardinality(toAdd);

        assertEq(oracle.currentCardinality(), expectedCardinality + toAdd);
    }
}

contract OracleUniV3TWAP_ArbiMain_WETHUSDC_ForkTest is OracleUniV3TWAP_ArbiMain_USDCWETH_ForkTest {
    function _config() internal override {
        super._config();
        baseToken = Const.ArbiMain_USDC;
        quoteToken = Const.ArbiMain_WETH;

        // 0.00036 ETH (= 1e18 / 2713) for 1e6 USDC (1 USDC)
        expectedCurPrice = 368_559_882_855_728;
        expectedPriceTwapWindowAgo = 367_602_919_598_965;
    }
}

contract OracleUniV3TWAP_ArbiSepolia_USDCWBTC_ForkTest is OracleUniV3TWAP_ArbiMain_USDCWETH_ForkTest {
    function _startFork() internal override {
        vm.createSelectFork(vm.envString("ARBITRUM_SEPOLIA_RPC"), 72_779_252);
    }

    function _config() internal override {
        super._config();
        router = Const.ArbiSep_UniRouter;
        baseToken = 0x0d64F70fAd5897d752c6e9e9a80ac3C978BF6897; // WBTC arbi-sep
        quoteToken = 0xbDCc1D2ADE76E4A02539674D6D03E4bf571Da712; // USDC arbi-sep
        pool = 0xa9933Deb1cEB37163f7F601eb69Dc923cAD3fcBc;

        sequencerFeedExists = false;
        sequencerFeed = address(0);

        expectedCardinality = 1000;
        // price is for 1e8 WBTC in USDC (because WBTC is 8 decimals)
        expectedCurPrice = 59_251_772_387; // 59000 * 1e6 (USDC decimals)
        expectedPriceTwapWindowAgo = 59_245_847_803;
    }
}

contract OracleUniV3TWAP_ArbiMain_NewPool_ForkTest is
    OracleUniV3TWAP_ArbiMain_USDCWETH_ForkTest,
    UniswapNewPoolHelper
{
    uint initialAmount = 10 ether;
    int24 tickSpacing = 10;
    address positionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88; // arbi-main

    function _setUp() internal virtual override {
        super._setUp();

        (baseToken, quoteToken) = deployTokens();

        expectedCardinality = uint16(twapWindow);

        PoolParams memory poolParams = PoolParams({
            token1: baseToken,
            token2: quoteToken,
            router: router,
            positionManager: positionManager,
            feeTier: feeTier,
            cardinality: expectedCardinality,
            initialAmount: initialAmount,
            tickSpacing: tickSpacing
        });

        pool = setupNewPool(poolParams);

        // add observations for twice the window duration for testing pastPrice
        for (uint i; i < 2 * twapWindow / 60; ++i) {
            skip(60); // skip 1 minute
            provideAmount1to1(poolParams, 1); // provide 1 wei to record an observation
        }

        expectedCurPrice = 1 ether;
        expectedPriceTwapWindowAgo = expectedCurPrice;
    }
}

contract OracleUniV3TWAP_ArbiSepolia_NewPool_ForkTest is OracleUniV3TWAP_ArbiMain_NewPool_ForkTest {
    function _startFork() internal override {
        vm.createSelectFork(vm.envString("ARBITRUM_SEPOLIA_RPC"), 72_779_252);
    }

    function _config() internal override {
        super._config();
        router = Const.ArbiSep_UniRouter;
        positionManager = Const.ArbiSep_UniPosMan;

        sequencerFeedExists = false;
        sequencerFeed = address(0);
    }
}
