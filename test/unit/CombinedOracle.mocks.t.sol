// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";

import { ChainlinkOracle, IERC20Metadata, IChainlinkFeedLike } from "../../src/ChainlinkOracle.sol";
import { CombinedOracle } from "../../src/CombinedOracle.sol";
import { MockChainlinkFeed } from "../utils/MockChainlinkFeed.sol";

contract CombinedOracleTest is Test {
    address constant VIRTUAL_ASSET = address(type(uint160).max); // 0xff..ff

    CombinedOracle public comboOracle;
    ChainlinkOracle public oracle_1;
    ChainlinkOracle public oracle_2;

    address mockSequencerFeed = address(0); // disabled
    uint sequencerGracePeriod = 1 hours;

    // feed 1
    MockChainlinkFeed mockFeed1; // ETH / USD
    address baseToken1 = address(0x100);
    address crossToken = address(0x300);
    bool public invert_1 = false;
    uint8 feed1Decimals = 8;
    uint8 baseDecimals1 = 18;
    uint8 crossDecimals = 6;
    uint unit1Price = 1000;

    // feed 2
    MockChainlinkFeed mockFeed2; // USDC / USD
    address baseToken2 = address(0x200);
    bool public invert_2 = true;
    uint8 feed2Decimals = 8;
    uint8 baseDecimals2 = 6;
    uint unit2Price = 2;

    string defaultDescription = "Comb(CL(feed1)|inv(CL(feed2)))";

    int feed1Answer;
    uint expectedOraclePrice1;
    int feed2Answer;
    uint expectedOraclePrice2;
    uint expectedComboPrice;

    uint maxStaleness = 100;

    function setUp() public {
        mockDecimalCalls();
        mockFeed1 = new MockChainlinkFeed(feed1Decimals, "feed1");
        mockFeed2 = new MockChainlinkFeed(feed2Decimals, "feed2");
        oracle_1 = new ChainlinkOracle(
            baseToken1, crossToken, address(mockFeed1), "feed1", maxStaleness, mockSequencerFeed
        );
        oracle_2 = new ChainlinkOracle(
            baseToken2, crossToken, address(mockFeed2), "feed2", maxStaleness, mockSequencerFeed
        );
        comboOracle = new CombinedOracle(
            baseToken1,
            baseToken2,
            address(oracle_1),
            invert_1,
            address(oracle_2),
            invert_2,
            defaultDescription
        );
        vm.clearMockedCalls();
        // roll into future to avoid underflow with timestamps
        skip(sequencerGracePeriod * 2);
        // calculate prices
        calculatePrices();
    }

    function mockDecimalCalls() internal {
        // Mock the decimals call
        vm.mockCall(baseToken1, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(baseDecimals1));
        vm.mockCall(baseToken2, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(baseDecimals2));
        vm.mockCall(crossToken, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(crossDecimals));
    }

    function setSequencer() internal {
        // redeploy
        mockSequencerFeed = makeAddr("feed");
        setUp();
        // check feed set on direct oracles
        assertEq(address(oracle_1.sequencerChainlinkFeed()), mockSequencerFeed);
        assertEq(address(oracle_2.sequencerChainlinkFeed()), mockSequencerFeed);
        // check that combo has still no sequencer feed
        assertEq(address(comboOracle.sequencerChainlinkFeed()), address(0));
    }

    function calculatePrices() internal {
        feed1Answer = int(unit1Price * 10 ** feed1Decimals);
        expectedOraclePrice1 = unit1Price * 10 ** crossDecimals;

        feed2Answer = int(unit2Price * 10 ** feed2Decimals);
        expectedOraclePrice2 = unit2Price * 10 ** crossDecimals;

        // assumes output is base2
        expectedComboPrice = unit1Price * (10 ** baseDecimals2) / unit2Price;
    }

    function invert(uint currentPrice, uint baseDecimalsCurrent, uint quoteDecimalsCurrent)
        internal
        pure
        returns (uint)
    {
        return 10 ** (baseDecimalsCurrent + quoteDecimalsCurrent) / currentPrice;
    }

    function basicPriceCheck(uint expectedPrice, uint expectedInverse) internal {
        mockFeed1.setLatestAnswer(feed1Answer, block.timestamp);
        assertEq(oracle_1.currentPrice(), expectedOraclePrice1);
        mockFeed2.setLatestAnswer(feed2Answer, block.timestamp);
        assertEq(oracle_2.currentPrice(), expectedOraclePrice2);

        // check expected forward
        assertEq(expectedComboPrice, expectedPrice);
        assertEq(comboOracle.currentPrice(), expectedComboPrice);

        // check expected inverse
        assertEq(invert(expectedComboPrice, baseDecimals1, baseDecimals2), expectedInverse);
        assertEq(comboOracle.inversePrice(), expectedInverse);

        // make base1 more expensive
        if (invert_1) {
            // inverted: base1 is from
            mockFeed1.setLatestAnswer(feed1Answer / 100, block.timestamp);
        } else {
            // base1 is to
            mockFeed1.setLatestAnswer(feed1Answer * 100, block.timestamp);
        }
        assertEq(comboOracle.currentPrice(), expectedComboPrice * 100);
        assertEq(comboOracle.inversePrice(), expectedInverse / 100);

        // make base2 more expensive
        mockFeed1.setLatestAnswer(feed1Answer, block.timestamp);
        if (invert_2) {
            // inverted: base2 is from
            mockFeed2.setLatestAnswer(feed2Answer * 100, block.timestamp);
        } else {
            // base2 is to
            mockFeed2.setLatestAnswer(feed2Answer / 100, block.timestamp);
        }
        assertEq(comboOracle.currentPrice(), expectedComboPrice / 100);
        assertEq(comboOracle.inversePrice(), expectedInverse * 100);
    }

    // effects tests

    function test_constructor() public {
        setUp();
        // BaseTakerOracle
        assertEq(comboOracle.VIRTUAL_ASSET(), VIRTUAL_ASSET);
        assertEq(comboOracle.baseToken(), baseToken1);
        assertEq(comboOracle.quoteToken(), baseToken2);
        assertEq(comboOracle.description(), defaultDescription);
        assertEq(comboOracle.baseUnitAmount(), 10 ** baseDecimals1);
        assertEq(comboOracle.quoteUnitAmount(), 10 ** baseDecimals2);
        assertEq(address(comboOracle.sequencerChainlinkFeed()), address(0));
        // CombinedOracle
        assertEq(comboOracle.VERSION(), "0.2.0");
        assertEq(address(comboOracle.oracle_1()), address(oracle_1));
        assertEq(address(comboOracle.oracle_2()), address(oracle_2));
        assertEq(comboOracle.invert_1(), invert_1);
        assertEq(comboOracle.invert_2(), invert_2);
    }

    function test_virtual_assets() public {
        address _temp = baseToken1;
        baseToken1 = VIRTUAL_ASSET;
        setUp();
        assertEq(comboOracle.baseUnitAmount(), 1 ether);
        assertEq(comboOracle.quoteUnitAmount(), 10 ** baseDecimals2);

        baseToken1 = _temp;
        baseToken2 = VIRTUAL_ASSET;
        setUp();
        assertEq(comboOracle.baseUnitAmount(), 10 ** baseDecimals1);
        assertEq(comboOracle.quoteUnitAmount(), 1 ether);
    }

    function testPrices_simple() public {
        // default starting values
        // from base1 to base2: ( 1000 / 2 ) * 1e6 -> 500e6
        // from base2 to base1: ( 2 / 1000 ) * 1e18 -> 0.002e18
        basicPriceCheck(500e6, 0.002e18);
    }

    function testPrices_decimals() public {
        baseDecimals1 = 4;
        baseDecimals2 = 8;
        crossDecimals = 6;
        crossDecimals = crossDecimals;
        setUp();
        // from base1 to base2: ( 1000 / 2 ) * 1e8 -> 500e8
        // from base2 to base1: ( 2 / 1000 ) * 1e4 -> 0.002e4
        basicPriceCheck(500e8, 0.002e4);
    }

    function testPrices_inverts_false_false() public {
        mockDecimalCalls();
        // flip second oracle
        oracle_2 = new ChainlinkOracle(
            crossToken, baseToken2, address(mockFeed2), "feed2", maxStaleness, mockSequencerFeed
        );
        invert_2 = false;
        defaultDescription = "Comb(CL(feed1)|CL(feed2))";
        comboOracle = new CombinedOracle(
            baseToken1,
            baseToken2,
            address(oracle_1),
            invert_1,
            address(oracle_2),
            invert_2,
            defaultDescription
        );
        assertEq(comboOracle.description(), defaultDescription);
        // 1: as before
        // 2: cross -> base2
        feed2Answer = int(10 ** feed2Decimals / unit2Price);
        expectedOraclePrice2 = 10 ** baseDecimals2 / unit2Price;

        // from base1 to base2: ( 1000 / 2 ) * 1e6 -> 500e6
        // from base2 to base1: ( 2 / 1000 ) * 1e18 -> 0.002e18
        basicPriceCheck(500e6, 0.002e18);
    }

    function testPrices_inverts_true_false() public {
        mockDecimalCalls();
        // flip first oracle
        oracle_1 = new ChainlinkOracle(
            crossToken, baseToken1, address(mockFeed1), "feed1", maxStaleness, mockSequencerFeed
        );
        // flip second oracle
        oracle_2 = new ChainlinkOracle(
            crossToken, baseToken2, address(mockFeed2), "feed2", maxStaleness, mockSequencerFeed
        );
        invert_1 = true;
        invert_2 = false;
        defaultDescription = "Comb(inv(CL(feed1))|CL(feed2))";
        comboOracle = new CombinedOracle(
            baseToken1,
            baseToken2,
            address(oracle_1),
            invert_1,
            address(oracle_2),
            invert_2,
            defaultDescription
        );
        assertEq(comboOracle.description(), defaultDescription);
        // 1: cross -> base1
        feed1Answer = int(10 ** feed1Decimals / unit1Price);
        expectedOraclePrice1 = 10 ** baseDecimals1 / unit1Price;
        // 2: cross -> base2
        feed2Answer = int(10 ** feed2Decimals / unit2Price);
        expectedOraclePrice2 = 10 ** baseDecimals2 / unit2Price;

        // from base1 to base2: ( 1000 / 2 ) * 1e6 -> 500e6
        // from base2 to base1: ( 2 / 1000 ) * 1e18 -> 0.002e18
        basicPriceCheck(500e6, 0.002e18);
    }

    function testPrices_inverts_true_true() public {
        mockDecimalCalls();
        // flip first oracle
        oracle_1 = new ChainlinkOracle(
            crossToken, baseToken1, address(mockFeed1), "feed1", maxStaleness, mockSequencerFeed
        );
        invert_1 = true;
        defaultDescription = "Comb(inv(CL(feed1))|inv(CL(feed2)))";
        comboOracle = new CombinedOracle(
            baseToken1,
            baseToken2,
            address(oracle_1),
            invert_1,
            address(oracle_2),
            invert_2,
            defaultDescription
        );
        assertEq(comboOracle.description(), defaultDescription);
        // 1: cross -> base1
        feed1Answer = int(10 ** feed1Decimals / unit1Price);
        expectedOraclePrice1 = 10 ** baseDecimals1 / unit1Price;

        // from base1 to base2: ( 1000 / 2 ) * 1e6 -> 500e6
        // from base2 to base1: ( 2 / 1000 ) * 1e18 -> 0.002e18
        basicPriceCheck(500e6, 0.002e18);
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
        comboOracle.sequencerLiveFor(0);
        vm.expectRevert("sequencer uptime feed unset");
        comboOracle.sequencerLiveFor(1000);

        // price works (oracle feed not called)
        mockFeed1.setLatestAnswer(feed1Answer, block.timestamp);
        mockFeed2.setLatestAnswer(feed2Answer, block.timestamp);
        assertEq(comboOracle.currentPrice(), expectedComboPrice);
        assertEq(comboOracle.inversePrice(), invert(expectedComboPrice, baseDecimals1, baseDecimals2));
    }

    function test_sequencerViewAndReverts_sequencerUp() public {
        setSequencer();

        // sequencer up (answer = 0) for 1 hour
        vm.mockCall(
            mockSequencerFeed,
            abi.encodeCall(IChainlinkFeedLike.latestRoundData, ()),
            abi.encode(0, 0, block.timestamp - sequencerGracePeriod + 1, 0, 0)
        );
        // direct oracles revert
        assertFalse(oracle_1.sequencerLiveFor(sequencerGracePeriod));
        vm.expectRevert("ChainlinkOracle: sequencer uptime interrupted");
        oracle_1.currentPrice();

        // combo oracle has no sequencer feed
        vm.expectRevert("sequencer uptime feed unset");
        comboOracle.sequencerLiveFor(0);

        // but it reverts for prices
        vm.expectRevert("ChainlinkOracle: sequencer uptime interrupted");
        comboOracle.currentPrice();

        skip(1);
        mockFeed1.setLatestAnswer(feed1Answer, block.timestamp);
        assertEq(oracle_1.currentPrice(), expectedOraclePrice1);
        mockFeed2.setLatestAnswer(feed2Answer, block.timestamp);
        assertEq(oracle_2.currentPrice(), expectedOraclePrice2);

        assertEq(comboOracle.currentPrice(), expectedComboPrice);
        assertEq(comboOracle.inversePrice(), invert(expectedComboPrice, baseDecimals1, baseDecimals2));
    }

    function test_conversions() public view {
        assertEq(comboOracle.baseUnitAmount(), 1 ether);
        // to base
        assertEq(comboOracle.convertToBaseAmount(1, 1000 ether), 0);
        assertEq(comboOracle.convertToBaseAmount(1 ether, 1000 ether), 1 ether / 1000);
        // to quote
        assertEq(comboOracle.convertToQuoteAmount(1, 1000 ether), 1000);
        assertEq(comboOracle.convertToQuoteAmount(1, 0.1 ether), 0);
    }

    // revert tests
    function test_revert_constructor_mismatches() public {
        mockDecimalCalls();

        // base
        vm.expectRevert("CombinedOracle: base argument mismatch");
        comboOracle = new CombinedOracle(
            baseToken1, baseToken2, address(oracle_2), invert_1, address(oracle_1), invert_2, ""
        );
        vm.expectRevert("CombinedOracle: base argument mismatch");
        comboOracle = new CombinedOracle(
            baseToken2, baseToken2, address(oracle_1), invert_1, address(oracle_2), invert_2, ""
        );

        // quote
        vm.expectRevert("CombinedOracle: quote argument mismatch");
        comboOracle = new CombinedOracle(
            baseToken1, crossToken, address(oracle_1), invert_1, address(oracle_2), invert_2, ""
        );
        vm.expectRevert("CombinedOracle: quote argument mismatch");
        comboOracle = new CombinedOracle(
            baseToken1, baseToken2, address(oracle_1), invert_1, address(oracle_1), invert_2, ""
        );

        // cross
        vm.expectRevert("CombinedOracle: cross token mismatch");
        comboOracle = new CombinedOracle(
            baseToken1, crossToken, address(oracle_1), invert_1, address(oracle_2), !invert_2, ""
        );
        vm.expectRevert("CombinedOracle: cross token mismatch");
        comboOracle = new CombinedOracle(
            crossToken, baseToken2, address(oracle_1), !invert_1, address(oracle_2), invert_2, ""
        );

        // description mismatch
        vm.expectRevert("CombinedOracle: description mismatch");
        comboOracle = new CombinedOracle(
            baseToken1, baseToken2, address(oracle_1), invert_1, address(oracle_2), invert_2, ""
        );
        vm.expectRevert("CombinedOracle: description mismatch");
        comboOracle = new CombinedOracle(
            baseToken1,
            baseToken2,
            address(oracle_1),
            invert_1,
            address(oracle_2),
            invert_2,
            string.concat(defaultDescription, "nope")
        );
    }

    function test_revert_prices() public {
        mockFeed1.setLatestAnswer(feed1Answer, block.timestamp - maxStaleness - 1);
        mockFeed2.setLatestAnswer(feed1Answer, block.timestamp - maxStaleness - 1);
        vm.expectRevert("ChainlinkOracle: stale price");
        oracle_1.currentPrice();
        vm.expectRevert("ChainlinkOracle: stale price");
        oracle_1.inversePrice();
        vm.expectRevert("ChainlinkOracle: stale price");
        oracle_2.currentPrice();
        vm.expectRevert("ChainlinkOracle: stale price");
        oracle_2.inversePrice();
        vm.expectRevert("ChainlinkOracle: stale price");
        comboOracle.currentPrice();
        vm.expectRevert("ChainlinkOracle: stale price");
        comboOracle.inversePrice();
        // fix oracle 1
        mockFeed1.setLatestAnswer(feed1Answer, block.timestamp - maxStaleness);
        assertEq(oracle_1.currentPrice(), expectedOraclePrice1);
        // 2 still broken
        vm.expectRevert("ChainlinkOracle: stale price");
        oracle_2.currentPrice();
        // combo still broken because of 2
        vm.expectRevert("ChainlinkOracle: stale price");
        comboOracle.currentPrice();
        // fix 2
        mockFeed2.setLatestAnswer(feed2Answer, block.timestamp - maxStaleness);
        // prices work
        assertEq(comboOracle.currentPrice(), expectedComboPrice);

        // set to not stale
        mockFeed1.setLatestAnswer(feed1Answer, block.timestamp - maxStaleness);
        assertEq(comboOracle.currentPrice(), expectedComboPrice);
        assertEq(comboOracle.inversePrice(), invert(expectedComboPrice, baseDecimals1, baseDecimals2));

        skip(1);
        // stale again
        vm.expectRevert("ChainlinkOracle: stale price");
        comboOracle.currentPrice();
        vm.expectRevert("ChainlinkOracle: stale price");
        comboOracle.inversePrice();

        // set to invalid
        mockFeed1.setLatestAnswer(0, block.timestamp);
        mockFeed2.setLatestAnswer(0, block.timestamp);
        vm.expectRevert("ChainlinkOracle: invalid price");
        comboOracle.currentPrice();
        vm.expectRevert("ChainlinkOracle: invalid price");
        comboOracle.inversePrice();

        mockFeed1.setLatestAnswer(-1, block.timestamp);
        mockFeed2.setLatestAnswer(-1, block.timestamp);
        vm.expectRevert("ChainlinkOracle: invalid price");
        comboOracle.currentPrice();
        vm.expectRevert("ChainlinkOracle: invalid price");
        comboOracle.inversePrice();
    }
}
