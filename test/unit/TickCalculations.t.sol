// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import { TickCalculations } from "../../src/libs/TickCalculations.sol";

contract TickCalculationsTest is Test {

    function setUp() public {

    }

    function test_bpsToTick() public {
        // tickScaleFactor = 1 (100%, 50%, 1%, 0.1%)
        assertEq(TickCalculations.bpsToTick(10_000, 1), 10_000);
        assertEq(TickCalculations.bpsToTick(5_000, 1), 5_000);
        assertEq(TickCalculations.bpsToTick(100, 1), 100);
        assertEq(TickCalculations.bpsToTick(1, 1), 1);

        // tickScaleFactor = 10 (100%, 50%, 1%)
        assertEq(TickCalculations.bpsToTick(10_000, 10), 1_000);
        assertEq(TickCalculations.bpsToTick(5_000, 10), 500);
        assertEq(TickCalculations.bpsToTick(100, 10), 10);

        // tickScaleFactor = 100 (100%, 50%, 1%)
        assertEq(TickCalculations.bpsToTick(10_000, 100), 100);
        assertEq(TickCalculations.bpsToTick(5_000, 100), 50);
        assertEq(TickCalculations.bpsToTick(100, 100), 1);
    }

    function test_tickToBps() public {
        // tickScaleFactor = 1 (100%, 50%, 1%, 0.1%)
        assertEq(TickCalculations.tickToBps(10_000, 1), 10_000);
        assertEq(TickCalculations.tickToBps(5_000, 1), 5_000);
        assertEq(TickCalculations.tickToBps(100, 1), 100);
        assertEq(TickCalculations.tickToBps(1, 1), 1);

        // tickScaleFactor = 10 (100%, 50%, 1%)
        assertEq(TickCalculations.tickToBps(1_000, 10), 10_000);
        assertEq(TickCalculations.tickToBps(500, 10), 5_000);
        assertEq(TickCalculations.tickToBps(10, 10), 100);

        // tickScaleFactor = 100 (100%, 50%, 1%)
        assertEq(TickCalculations.tickToBps(100, 100), 10_000);
        assertEq(TickCalculations.tickToBps(50, 100), 5_000);
        assertEq(TickCalculations.tickToBps(1, 100), 100);
    }

    function test_tickToPrice() public {
        // tickScaleFactor = 1
        assertEq(TickCalculations.tickToPrice(10_000, 1, 1e18), 1e18);
        assertEq(TickCalculations.tickToPrice(5_000, 1, 1e18), 0.5e18);

        // tickScaleFactor = 10
        assertEq(TickCalculations.tickToPrice(1_000, 10, 1e18), 1e18);
        assertEq(TickCalculations.tickToPrice(100, 10, 1e18), 0.1e18);

        // tickScaleFactor = 100
        assertEq(TickCalculations.tickToPrice(100, 100, 1e18), 1e18);
        assertEq(TickCalculations.tickToPrice(10, 100, 1e18), 0.1e18);
    }

    function test_priceToTick() public {
        // tickScaleFactor = 1a
        assertEq(TickCalculations.priceToTick(1e18, 1, 1e18), 10_000);
        assertEq(TickCalculations.priceToTick(2e18, 1, 1e18), 20_000);
        assertEq(TickCalculations.priceToTick(0.5e18, 1, 1e18), 5_000);

        // tickScaleFactor = 10
        assertEq(TickCalculations.priceToTick(1e18, 10, 1e18), 1_000);
        assertEq(TickCalculations.priceToTick(0.1e18, 10, 1e18), 100);
        assertEq(TickCalculations.priceToTick(0.01e18, 10, 1e18), 10);
        assertEq(TickCalculations.priceToTick(1e18, 10, 2e18), 500);
        assertEq(TickCalculations.priceToTick(2e18, 10, 1e18), 2_000);

        // tickScaleFactor = 100
        assertEq(TickCalculations.priceToTick(1e18, 100, 1e18), 100);
        assertEq(TickCalculations.priceToTick(0.1e18, 100, 1e18), 10);
        assertEq(TickCalculations.priceToTick(0.01e18, 100, 1e18), 1);
        assertEq(TickCalculations.priceToTick(1e18, 100, 2e18), 50);
    }
}