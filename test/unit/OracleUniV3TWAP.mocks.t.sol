// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import "forge-std/Test.sol";
import { OracleUniV3TWAP } from "../../src/OracleUniV3TWAP.sol";
import {
    IUniswapV3Pool,
    IUniswapV3PoolState,
    IUniswapV3PoolActions,
    IUniswapV3PoolDerivedState
} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IPeripheryImmutableState } from
    "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";

contract OracleUniV3TWAPTest is Test {
    OracleUniV3TWAP public oracle;

    address baseToken = address(0x10);
    address quoteToken = address(0x20);
    uint24 feeTier = 3000;
    uint32 twapWindow = 300;

    address mockPool = address(0x30);
    address mockFactory = address(0x40);
    address mockRouter = address(0x50);

    error OLD(); // when price is not available

    /*
    tick math help:
        https://uniswapv3book.com/milestone_0/uniswap-v3.html?highlight=tick#ticks
        https://docs.uniswap.org/contracts/v3/reference/core/libraries/TickMath
        tick to price: 1.0001 ^ (tick)
        price to tick: math.log2(1000) / math.log2(1.0001)
    */
    int24 tick1000 = 69_082;
    uint priceTick1000 = 1_000_099_338_977_258_828_485;

    function setUp() public {
        mockRouterAndFactoryCalls();
        oracle = new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow, mockRouter);
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
    }

    function mockObserve(int24 tick, uint32 ago) internal {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = ago + twapWindow;
        secondsAgos[1] = ago;

        int56[] memory tickCumulatives = new int56[](2);
        tickCumulatives[0] = int56(tick) * 300;
        tickCumulatives[1] = int56(tick) * (300 + int56(uint56(twapWindow)));
        uint160[] memory secondsPerLiquidityCumulativeX128s = new uint160[](2);

        vm.mockCall(
            mockPool,
            abi.encodeCall(IUniswapV3PoolDerivedState.observe, (secondsAgos)),
            abi.encode(tickCumulatives, secondsPerLiquidityCumulativeX128s)
        );
    }

    // effects tests

    function test_constructor() public {
        mockRouterAndFactoryCalls();
        oracle = new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow, mockRouter);
        assertEq(oracle.VERSION(), "0.2.0");
        assertEq(oracle.MIN_TWAP_WINDOW(), 300);
        assertEq(oracle.baseToken(), baseToken);
        assertEq(oracle.quoteToken(), quoteToken);
        assertEq(oracle.feeTier(), feeTier);
        assertEq(oracle.twapWindow(), twapWindow);
        assertEq(address(oracle.pool()), mockPool);
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

    function test_currentPrice() public {
        int24 mockTick = tick1000;
        mockObserve(mockTick, 0);

        uint price = oracle.currentPrice();
        assertEq(price, priceTick1000);
    }

    function test_pastPrice() public {
        int24 mockTick = tick1000;
        mockObserve(mockTick, 60);

        uint32 pastTimestamp = uint32(block.timestamp) - 60;
        uint price = oracle.pastPrice(pastTimestamp);
        assertEq(price, priceTick1000);
    }

    function test_pastPriceWithFallback() public {
        int24 mockTick = tick1000;
        mockObserve(mockTick, 60);

        uint32 pastTimestamp = uint32(block.timestamp) - 60;
        (uint price, bool pastPriceOk) = oracle.pastPriceWithFallback(pastTimestamp);
        assertEq(price, priceTick1000);
        assertTrue(pastPriceOk);
    }

    function test_pastPriceWithFallback_unavailableHistorical() public {
        // Mock observe to revert for historical data
        uint32 ago = 60;
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = ago + twapWindow;
        secondsAgos[1] = ago;
        vm.mockCallRevert(
            mockPool,
            abi.encodeCall(IUniswapV3PoolDerivedState.observe, (secondsAgos)),
            abi.encodeWithSelector(OLD.selector)
        );

        // Mock current price
        int24 currentTick = tick1000;
        mockObserve(currentTick, 0);

        uint32 pastTimestamp = uint32(block.timestamp) - ago;

        // past price should revert
        vm.expectRevert(abi.encodeWithSelector(OLD.selector));
        oracle.pastPrice(pastTimestamp);

        // fallback should succeed
        (uint price, bool pastPriceOk) = oracle.pastPriceWithFallback(pastTimestamp);

        assertEq(price, priceTick1000);
        assertFalse(pastPriceOk);
    }

    function test_differentTWAPWindow() public {
        twapWindow = 600; // 10 minutes
        mockRouterAndFactoryCalls();
        OracleUniV3TWAP newOracle =
            new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow, mockRouter);

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

    // revert tests

    function test_revert_constructor_invalidPool() public {
        // reverting factory view
        vm.expectRevert(new bytes(0));
        new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow, address(0));
    }

    function test_revert_constructor_invalidTWAPWindow() public {
        vm.expectRevert("twap window too short");
        new OracleUniV3TWAP(baseToken, quoteToken, feeTier, twapWindow - 1, mockRouter);
    }
}
