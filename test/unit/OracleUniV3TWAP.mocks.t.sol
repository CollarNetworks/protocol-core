// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import {
    IUniswapV3Pool,
    IUniswapV3PoolState,
    IUniswapV3PoolActions,
    IUniswapV3PoolDerivedState
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IPeripheryImmutableState } from
    "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";

import { IERC20Metadata, IChainlinkFeedLike } from "../../src/base/BaseTakerOracle.sol";
import { OracleUniV3TWAP } from "../utils/OracleUniV3TWAP.sol";

contract OracleUniV3TWAPTest is Test {
    OracleUniV3TWAP public oracle;

    address baseToken = address(0x10);
    address quoteToken = address(0x20);
    uint24 feeTier = 3000;
    uint32 twapWindow = 300;

    address mockPool = address(0x30);
    address mockFactory = address(0x40);
    address mockRouter = address(0x50);
    address mockSequencerFeed = address(0); // disabled

    error OLD(); // when price is not available

    /*
    tick math help:
        https://uniswapv3book.com/milestone_0/uniswap-v3.html?highlight=tick#ticks
        https://docs.uniswap.org/contracts/v3/reference/core/libraries/TickMath
        tick to price: 1.0001 ^ (tick)
        price to tick: math.log2(price-ratio) / math.log2(1.0001)
    */
    int24 tick1000 = 69_082;
    uint priceTick1000 = 1_000_099_338_977_258_828_485; // 1000
    int24 tickNeg1000 = -69_082;
    uint priceTickInverse1000 = 999_900_670_889_993; // 0.00099
    uint priceTickInverse1001 = 999_800_690_820_911; // 0.00099

    uint8 decimals = 18;

    function setUp() public {
        mockRouterAndFactoryCalls();
        oracle =
            new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow, mockRouter, mockSequencerFeed);
        vm.clearMockedCalls();
        // roll into future to avoid underflow with timestamps
        skip(1000);
    }

    function mockRouterAndFactoryCalls() internal {
        // Mock the factory address call
        vm.mockCall(mockRouter, abi.encodeCall(IPeripheryImmutableState.factory, ()), abi.encode(mockFactory));

        // Mock the getPool call
        vm.mockCall(
            mockFactory,
            abi.encodeCall(IUniswapV3Factory.getPool, (baseToken, quoteToken, feeTier)),
            abi.encode(mockPool)
        );

        // Mock the decimals call
        vm.mockCall(baseToken, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(decimals));
        vm.mockCall(quoteToken, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(decimals));
    }

    function mockObserve(int24 tick, uint32 ago) internal {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = ago + twapWindow;
        secondsAgos[1] = ago;

        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = int56(tick) * 300;
        tickCumulatives[1] = int56(tick) * (300 + int56(uint56(twapWindow)));

        vm.mockCall(
            mockPool,
            abi.encodeCall(IUniswapV3PoolDerivedState.observe, (secondsAgos)),
            abi.encode(tickCumulatives, new uint160[](2))
        );
    }

    function setSequencer() internal {
        // redeploy
        mockSequencerFeed = makeAddr("feed");
        setUp();
        // check
        assertEq(address(oracle.sequencerChainlinkFeed()), mockSequencerFeed);
    }

    // effects tests

    function test_constructor() public {
        mockRouterAndFactoryCalls();
        oracle =
            new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow, mockRouter, mockSequencerFeed);
        assertEq(oracle.VERSION(), "0.2.0");
        assertEq(oracle.MIN_TWAP_WINDOW(), 300);
        assertEq(oracle.baseToken(), baseToken);
        assertEq(oracle.quoteToken(), quoteToken);
        assertEq(oracle.baseUnitAmount(), 10 ** decimals);
        assertEq(oracle.feeTier(), feeTier);
        assertEq(oracle.twapWindow(), twapWindow);
        assertEq(address(oracle.pool()), mockPool);
        assertEq(address(oracle.sequencerChainlinkFeed()), address(0));

        // test different decimals
        decimals = 2;
        mockRouterAndFactoryCalls();
        oracle =
            new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow, mockRouter, mockSequencerFeed);
        assertEq(oracle.baseUnitAmount(), 10 ** decimals);
    }

    function test_currentCardinality() public {
        uint16 expectedCardinality = 100;
        vm.mockCall(
            mockPool,
            abi.encodeCall(IUniswapV3PoolState.slot0, ()),
            abi.encode(0, 0, 0, 0, expectedCardinality, 0, true)
        );

        assertEq(oracle.currentCardinality(), expectedCardinality);
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
        mockObserve(tick1000, 0);
        assertEq(oracle.currentPrice(), priceTick1000);
    }

    function test_sequencerViewAndReverts_sequencerUp() public {
        setSequencer();

        // sequencer up (answer = 0) for 1 hour
        vm.mockCall(
            mockSequencerFeed,
            abi.encodeCall(IChainlinkFeedLike.latestRoundData, ()),
            abi.encode(0, 0, block.timestamp - twapWindow + 1, 0, 0)
        );
        int24 mockTick = tick1000;

        // current works
        assertFalse(oracle.sequencerLiveFor(twapWindow));
        vm.expectRevert("sequencer uptime interrupted");
        oracle.currentPrice();

        skip(1);
        assertTrue(oracle.sequencerLiveFor(twapWindow));
        mockObserve(mockTick, 0);
        assertEq(oracle.currentPrice(), priceTick1000);

        assertFalse(oracle.sequencerLiveFor(twapWindow + 1));
    }

    function test_sequencerViewAndReverts_sequencerDown() public {
        setSequencer();

        // sequencer down (answer = 1) for 1 hour
        vm.mockCall(
            mockSequencerFeed,
            abi.encodeCall(IChainlinkFeedLike.latestRoundData, ()),
            abi.encode(0, 1, block.timestamp - twapWindow, 0, 0)
        );

        assertFalse(oracle.sequencerLiveFor(0));
        assertFalse(oracle.sequencerLiveFor(1500));

        vm.expectRevert("sequencer uptime interrupted");
        oracle.currentPrice();

        skip(1000);

        vm.expectRevert("sequencer uptime interrupted");
        oracle.currentPrice();
        assertFalse(oracle.sequencerLiveFor(0));
        assertFalse(oracle.sequencerLiveFor(1500));
    }

    function test_currentPrice() public {
        int24 mockTick = tick1000;
        mockObserve(mockTick, 0);

        uint price = oracle.currentPrice();
        assertEq(price, priceTick1000);
    }

    function test_currentPrice_negTick() public {
        int24 mockTick = tickNeg1000;
        mockObserve(mockTick, 0);

        uint price = oracle.currentPrice();
        assertEq(price, priceTickInverse1000);
    }

    function test_differentTWAPWindow() public {
        twapWindow = 600; // 10 minutes
        mockRouterAndFactoryCalls();
        OracleUniV3TWAP newOracle =
            new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow, mockRouter, mockSequencerFeed);

        int24 mockTick = tick1000;
        mockObserve(mockTick, 0);

        uint price = newOracle.currentPrice();
        assertEq(price, priceTick1000);
    }

    function test_increaseCardinality() public {
        uint16 initialCardinality = 50;
        uint16 toAdd = 50;
        uint16 newCardinality = initialCardinality + toAdd;

        vm.mockCall(
            mockPool,
            abi.encodeCall(IUniswapV3PoolState.slot0, ()),
            abi.encode(0, 0, 0, 0, initialCardinality, 0, true)
        );

        vm.expectCall(
            mockPool, abi.encodeCall(IUniswapV3PoolActions.increaseObservationCardinalityNext, newCardinality)
        );

        oracle.increaseCardinality(toAdd);
    }

    function test_negativeTickCumulativeDelta() public {
        // To cover the `tick--` branch in _getQoute

        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = int56(tickNeg1000) * 300;
        tickCumulatives[1] = int56(tickNeg1000) * (300 + int56(uint56(twapWindow))) - 1;
        // This creates a delta of -301
        // The delta (-301) divided by twapWindow (300) is -1 with a remainder

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapWindow;
        secondsAgos[1] = 0;

        vm.mockCall(
            mockPool,
            abi.encodeCall(IUniswapV3PoolDerivedState.observe, (secondsAgos)),
            abi.encode(tickCumulatives, new uint160[](2))
        );

        uint price = oracle.currentPrice();

        assertEq(price, priceTickInverse1001);
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

    function test_revert_constructor_invalidPool() public {
        vm.mockCall(quoteToken, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(decimals));
        vm.mockCall(baseToken, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(18));
        // reverting factory view
        vm.expectRevert(new bytes(0));
        new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow, address(0), mockSequencerFeed);
    }

    function test_revert_constructor_invalidTWAPWindow() public {
        vm.mockCall(quoteToken, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(decimals));
        vm.mockCall(baseToken, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(18));
        vm.expectRevert("twap window too short");
        new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow - 1, mockRouter, mockSequencerFeed);
    }

    function test_revert_constructor_invalidDecimals() public {
        // Mock the decimals call
        vm.mockCall(quoteToken, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(decimals));
        vm.mockCall(baseToken, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(39));
        vm.expectRevert("invalid base decimals");
        new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow, mockRouter, mockSequencerFeed);
    }
}
