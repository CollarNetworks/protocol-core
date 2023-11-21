// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "lib/forge-std/src/Test.sol";
import { TickCalculations } from "../../../src/liquidity/implementations/TickCalculations.sol";

contract TickCalculationsTest is Test {
    
    function setUp() public {

    }

    function test_bpsToTick() public {
        uint24 tick1_1 = TickCalculations.bpsToTick(100, 1);
        uint24 tick1_2 = TickCalculations.bpsToTick(5000, 1);
        uint24 tick1_3 = TickCalculations.bpsToTick(10000, 1);

        // 100 bps   @ scalefactor 1 = 1%   = tick 100
        // 5000 bps  @ scalefactor 1 = 50%  = tick 5000
        // 10000 bps @ scalefactor 1 = 100% = tick 10000

        assertEq(tick1_1, 100);
        assertEq(tick1_2, 5000);
        assertEq(tick1_3, 10000);

        uint24 tick2_1 = TickCalculations.bpsToTick(100, 2);
        uint24 tick2_2 = TickCalculations.bpsToTick(5000, 2);
        uint24 tick2_3 = TickCalculations.bpsToTick(10000, 2);

        // 100 bps   @ scalefactor 2 = 2%   = tick 50
        // 5000 bps  @ scalefactor 2 = 100% = tick 2500
        // 10000 bps @ scalefactor 2 = 200% = tick 5000

        assertEq(tick2_1, 50);
        assertEq(tick2_2, 2500);
        assertEq(tick2_3, 5000);
    }

    function test_tickToBps() public {
        uint256 bps1_1 = TickCalculations.tickToBps(100, 1);
        uint256 bps1_2 = TickCalculations.tickToBps(5000, 1);
        uint256 bps1_3 = TickCalculations.tickToBps(10000, 1);

        // 100 bps   @ scalefactor 1 = 1%   = tick 100
        // 5000 bps  @ scalefactor 1 = 50%  = tick 5000
        // 10000 bps @ scalefactor 1 = 100% = tick 10000

        assertEq(bps1_1, 100);
        assertEq(bps1_2, 5000);
        assertEq(bps1_3, 10000);

        uint256 bps2_1 = TickCalculations.tickToBps(50, 2);
        uint256 bps2_2 = TickCalculations.tickToBps(2500, 2);
        uint256 bps2_3 = TickCalculations.tickToBps(5000, 2);

        // 100 bps   @ scalefactor 2 = 2%   = tick 50
        // 5000 bps  @ scalefactor 2 = 100% = tick 2500
        // 10000 bps @ scalefactor 2 = 200% = tick 5000

        assertEq(bps2_1, 100);
        assertEq(bps2_2, 5000);
        assertEq(bps2_3, 10000);
    }

    function test_tickToPrice() public {
        uint256 price1_1 = TickCalculations.tickToPrice(100, 1, 1000);
        uint256 price1_2 = TickCalculations.tickToPrice(5000, 1, 1000);
        uint256 price1_3 = TickCalculations.tickToPrice(10000, 1, 1000);

        // tick 100 @ scalefactor 1 = 1% * 1000 starting price = 10
        // tick 5000 @ scalefactor 1 = 50% * 1000 starting price = 500
        // tick 10000 @ scalefactor 1 = 100% * 1000 starting price = 1000

        assertEq(price1_1, 10);
        assertEq(price1_2, 500);
        assertEq(price1_3, 1000);

        uint256 price2_1 = TickCalculations.tickToPrice(50, 2, 1000);
        uint256 price2_2 = TickCalculations.tickToPrice(2500, 2, 1000);
        uint256 price2_3 = TickCalculations.tickToPrice(5000, 2, 1000);

        // tick 50 @ scalefactor 2 = 2% * 1000 starting price = 20
        // tick 2500 @ scalefactor 2 = 100% * 1000 starting price = 1000
        // tick 5000 @ scalefactor 2 = 200% * 1000 starting price = 2000

        assertEq(price2_1, 20);
        assertEq(price2_2, 1000);
        assertEq(price2_3, 2000);
    }

    function test_priceToTick() public {
        uint24 tick1_1 = TickCalculations.priceToTick(10, 1, 1000);
        uint24 tick1_2 = TickCalculations.priceToTick(500, 1, 1000);
        uint24 tick1_3 = TickCalculations.priceToTick(1000, 1, 1000);

        // current price 10 @ starting 1000 = 1% @ scalefactor 1 = tick 100
        // current price 500 @ starting 1000 = 50% @ scalefactor 1 = tick 5000
        // current price 1000 @ starting 1000 = 100% @ scalefactor 1 = tick 10000

        assertEq(tick1_1, 100);
        assertEq(tick1_2, 5000);
        assertEq(tick1_3, 10000);

        uint24 tick2_1 = TickCalculations.priceToTick(20, 2, 1000);
        uint24 tick2_2 = TickCalculations.priceToTick(1000, 2, 1000);
        uint24 tick2_3 = TickCalculations.priceToTick(2000, 2, 1000);

        // current price 20 @ starting 1000 = 2% @ scalefactor 2 = tick 50
        // current price 1000 @ starting 1000 = 100% @ scalefactor 2 = tick 2500
        // current price 2000 @ starting 1000 = 200% @ scalefactor 2 = tick 5000

        assertEq(tick2_1, 50);
        assertEq(tick2_2, 2500);
        assertEq(tick2_3, 5000);
    }

}

