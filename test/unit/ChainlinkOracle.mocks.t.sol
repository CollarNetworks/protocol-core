// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { ChainlinkOracle, IERC20Metadata, IChainlinkFeedLike } from "../../src/ChainlinkOracle.sol";
import { MockChainlinkFeed } from "../utils/MockChainlinkFeed.sol";

contract ChainlinkOracleTest is Test {
    ChainlinkOracle public oracle;

    address constant VIRTUAL_ASSET = address(type(uint160).max); // 0xff..ff

    address baseToken = address(0x10);
    address quoteToken = address(0x20);

    MockChainlinkFeed mockFeed;
    address mockSequencerFeed = address(0); // disabled

    // feed
    uint8 feedDecimals = 8;
    string feedDescription = "MockFeed";
    uint8 baseDecimals = 18;
    uint8 quoteDecimals = 6;

    uint sequencerGracePeriod = 3600;

    uint maxStaleness = 100;
    uint unitPrice = 1000;
    int feedPrice = int(unitPrice * 10 ** feedDecimals);
    uint expectedPrice = unitPrice * 10 ** quoteDecimals;

    function setUp() public {
        mockDependencyCalls();
        mockFeed = new MockChainlinkFeed(feedDecimals, feedDescription);
        oracle = new ChainlinkOracle(
            baseToken, quoteToken, address(mockFeed), feedDescription, maxStaleness, mockSequencerFeed
        );
        vm.clearMockedCalls();
        // roll into future to avoid underflow with timestamps
        skip(sequencerGracePeriod * 2);
    }

    function mockDependencyCalls() internal {
        // Mock the decimals call
        vm.mockCall(baseToken, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(baseDecimals));
        vm.mockCall(quoteToken, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(quoteDecimals));
    }

    function setSequencer() internal {
        // redeploy
        mockSequencerFeed = makeAddr("feed");
        setUp();
        // check
        assertEq(address(oracle.sequencerChainlinkFeed()), mockSequencerFeed);
    }

    function invert(uint price) internal view returns (uint) {
        return 10 ** (baseDecimals + quoteDecimals) / price;
    }

    // effects tests

    function test_constructor() public {
        mockDependencyCalls();
        oracle = new ChainlinkOracle(
            baseToken, quoteToken, address(mockFeed), feedDescription, maxStaleness, mockSequencerFeed
        );
        assertEq(oracle.VERSION(), "0.2.0");
        assertEq(oracle.VIRTUAL_ASSET(), VIRTUAL_ASSET);
        assertEq(oracle.baseToken(), baseToken);
        assertEq(oracle.quoteToken(), quoteToken);
        assertEq(oracle.baseUnitAmount(), 10 ** baseDecimals);
        assertEq(oracle.quoteUnitAmount(), 10 ** quoteDecimals);
        assertEq(oracle.feedUnitAmount(), 10 ** feedDecimals);
        assertEq(oracle.maxStaleness(), maxStaleness);
        assertEq(oracle.MIN_SEQUENCER_UPTIME(), sequencerGracePeriod);
        assertEq(address(oracle.priceFeed()), address(mockFeed));
        assertEq(address(oracle.sequencerChainlinkFeed()), mockSequencerFeed);

        // test different decimals
        baseDecimals = 2;
        quoteDecimals = 3;
        feedDecimals = 4;
        mockDependencyCalls();
        mockFeed = new MockChainlinkFeed(feedDecimals, feedDescription);
        oracle = new ChainlinkOracle(
            baseToken, quoteToken, address(mockFeed), feedDescription, maxStaleness, mockSequencerFeed
        );
        assertEq(oracle.baseUnitAmount(), 10 ** baseDecimals);
        assertEq(oracle.quoteUnitAmount(), 10 ** quoteDecimals);
        assertEq(oracle.feedUnitAmount(), 10 ** feedDecimals);
    }

    function test_virtual_assets() public {
        mockDependencyCalls();
        oracle = new ChainlinkOracle(
            VIRTUAL_ASSET, quoteToken, address(mockFeed), feedDescription, maxStaleness, mockSequencerFeed
        );
        assertEq(oracle.baseUnitAmount(), 1 ether);
        assertEq(oracle.quoteUnitAmount(), 10 ** quoteDecimals);

        oracle = new ChainlinkOracle(
            baseToken, VIRTUAL_ASSET, address(mockFeed), feedDescription, maxStaleness, mockSequencerFeed
        );
        assertEq(oracle.baseUnitAmount(), 10 ** baseDecimals);
        assertEq(oracle.quoteUnitAmount(), 1 ether);
    }

    function test_revert_sequencer_notSet() public {
        // sequencer address returns "down", but it's 0 address so not checked
        vm.mockCall(
            mockSequencerFeed, // address 0 here
            abi.encodeCall(IChainlinkFeedLike.latestRoundData, ()),
            abi.encode(0, 1, 0, 0, 0)
        );
        // view reverts
        vm.expectRevert("sequencer uptime feed unset");
        oracle.sequencerLiveFor(0);
        vm.expectRevert("sequencer uptime feed unset");
        oracle.sequencerLiveFor(1000);

        // price works (oracle feed not called)
        mockFeed.setLatestAnswer(feedPrice, block.timestamp - maxStaleness);
        assertEq(oracle.currentPrice(), expectedPrice);
        assertEq(oracle.inversePrice(), invert(expectedPrice));
    }

    function test_sequencerViewAndReverts_sequencerUp() public {
        setSequencer();

        // sequencer up (answer = 0) for 1 hour
        vm.mockCall(
            mockSequencerFeed,
            abi.encodeCall(IChainlinkFeedLike.latestRoundData, ()),
            abi.encode(0, 0, block.timestamp - sequencerGracePeriod + 1, 0, 0)
        );
        // current works
        assertFalse(oracle.sequencerLiveFor(sequencerGracePeriod));
        vm.expectRevert("ChainlinkOracle: sequencer uptime interrupted");
        oracle.currentPrice();
        vm.expectRevert("ChainlinkOracle: sequencer uptime interrupted");
        oracle.inversePrice();

        skip(1);
        assertTrue(oracle.sequencerLiveFor(sequencerGracePeriod));
        mockFeed.setLatestAnswer(feedPrice, block.timestamp - maxStaleness);
        assertEq(oracle.currentPrice(), expectedPrice);
        assertEq(oracle.inversePrice(), invert(expectedPrice));

        assertFalse(oracle.sequencerLiveFor(sequencerGracePeriod + 1));
    }

    function test_sequencerViewAndReverts_sequencerDown() public {
        setSequencer();

        // sequencer down (answer = 1) for 1 hour
        vm.mockCall(
            mockSequencerFeed,
            abi.encodeCall(IChainlinkFeedLike.latestRoundData, ()),
            abi.encode(0, 1, block.timestamp - sequencerGracePeriod, 0, 0)
        );

        assertFalse(oracle.sequencerLiveFor(0));
        assertFalse(oracle.sequencerLiveFor(1500));

        vm.expectRevert("ChainlinkOracle: sequencer uptime interrupted");
        oracle.currentPrice();
        vm.expectRevert("ChainlinkOracle: sequencer uptime interrupted");
        oracle.inversePrice();

        skip(1000);

        vm.expectRevert("ChainlinkOracle: sequencer uptime interrupted");
        oracle.currentPrice();
        vm.expectRevert("ChainlinkOracle: sequencer uptime interrupted");
        oracle.inversePrice();
        assertFalse(oracle.sequencerLiveFor(0));
        assertFalse(oracle.sequencerLiveFor(1500));
    }

    function testPrices_simple() public {
        mockFeed.setLatestAnswer(feedPrice, block.timestamp - maxStaleness);
        assertEq(oracle.currentPrice(), expectedPrice);
        assertEq(oracle.inversePrice(), invert(expectedPrice));

        mockFeed.setLatestAnswer(feedPrice * 100, block.timestamp - maxStaleness);
        assertEq(oracle.currentPrice(), expectedPrice * 100);
        assertEq(oracle.inversePrice(), invert(expectedPrice) / 100);
    }

    function testPrices_decimals() public {
        baseDecimals = 2;
        quoteDecimals = 3;
        feedDecimals = 4;
        mockDependencyCalls();
        mockFeed = new MockChainlinkFeed(feedDecimals, feedDescription);
        oracle = new ChainlinkOracle(
            baseToken, quoteToken, address(mockFeed), feedDescription, maxStaleness, mockSequencerFeed
        );

        feedPrice = int(unitPrice * 10 ** feedDecimals);
        expectedPrice = unitPrice * 10 ** quoteDecimals;

        mockFeed.setLatestAnswer(feedPrice, block.timestamp - maxStaleness);
        assertEq(oracle.currentPrice(), expectedPrice);
        assertEq(oracle.inversePrice(), invert(expectedPrice));

        mockFeed.setLatestAnswer(feedPrice * 100, block.timestamp - maxStaleness);
        assertEq(oracle.currentPrice(), expectedPrice * 100);
        assertEq(oracle.inversePrice(), invert(expectedPrice) / 100);
    }

    function test_conversions() public view {
        assertEq(oracle.baseUnitAmount(), 1 ether);
        // to base
        assertEq(oracle.convertToBaseAmount(1, 1000 ether), 0);
        assertEq(oracle.convertToBaseAmount(1 ether, 1000 ether), 1 ether / 1000);
        // to quote
        assertEq(oracle.convertToQuoteAmount(1, 1000 ether), 1000);
        assertEq(oracle.convertToQuoteAmount(1, 0.1 ether), 0);
    }

    // revert tests
    function test_revert_constructor_staleness() public {
        mockDependencyCalls();
        vm.expectRevert("ChainlinkOracle: staleness out of range");
        oracle = new ChainlinkOracle(
            baseToken, quoteToken, address(mockFeed), feedDescription, 1 minutes - 1, mockSequencerFeed
        );
        vm.expectRevert("ChainlinkOracle: staleness out of range");
        oracle = new ChainlinkOracle(
            baseToken, quoteToken, address(mockFeed), feedDescription, 72 hours + 1, mockSequencerFeed
        );
    }

    function test_revert_constructor_description() public {
        mockDependencyCalls();
        mockFeed = new MockChainlinkFeed(feedDecimals, "Nope");
        vm.expectRevert("ChainlinkOracle: description mismatch");
        oracle = new ChainlinkOracle(
            baseToken, quoteToken, address(mockFeed), feedDescription, maxStaleness, mockSequencerFeed
        );
    }

    function test_revert_prices() public {
        mockFeed.setLatestAnswer(feedPrice, block.timestamp - maxStaleness - 1);
        vm.expectRevert("ChainlinkOracle: stale price");
        oracle.currentPrice();
        vm.expectRevert("ChainlinkOracle: stale price");
        oracle.inversePrice();

        // set to not stale
        mockFeed.setLatestAnswer(feedPrice, block.timestamp - maxStaleness);
        assertEq(oracle.currentPrice(), expectedPrice);
        assertEq(oracle.inversePrice(), invert(expectedPrice));

        skip(1);
        vm.expectRevert("ChainlinkOracle: stale price");
        oracle.currentPrice();
        vm.expectRevert("ChainlinkOracle: stale price");
        oracle.inversePrice();

        // set to invalid
        mockFeed.setLatestAnswer(0, block.timestamp);
        vm.expectRevert("ChainlinkOracle: invalid price");
        oracle.currentPrice();
        vm.expectRevert("ChainlinkOracle: invalid price");
        oracle.inversePrice();

        mockFeed.setLatestAnswer(-1, block.timestamp);
        vm.expectRevert("ChainlinkOracle: invalid price");
        oracle.currentPrice();
        vm.expectRevert("ChainlinkOracle: invalid price");
        oracle.inversePrice();
    }
}
