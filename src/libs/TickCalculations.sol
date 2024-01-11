// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

library TickCalculations {
    /// @notice Returns the tick matching the given bps
    /// @param bps The bps to convert to a tick
    /// @param tickScaleFactor The tickScaleFactor to use for the conversion
    function bpsToTick(uint256 bps, uint256 tickScaleFactor) public pure returns (uint24) {
        // 1 bps / tick @ tickScaleFactor 1
        // 10_000bps (100%) = tick # 10_000

        // 10 bps / tick @ tickScaleFactor 10
        // 10_000bps (100%) = tick # 1_000

        return uint24(bps / tickScaleFactor);
    }

    /// @notice Returns the bps matching the given tick
    /// @param tick The tick to convert to bps
    /// @param tickScaleFactor The tickScaleFactor to use for the conversion
    function tickToBps(uint24 tick, uint256 tickScaleFactor) public pure returns (uint256) {
        // 1 bps / tick @ tickScaleFactor 1
        // 10_000bps (100%) = tick # 10_000

        // 10 bps / tick @ tickScaleFactor 10
        // 10_000bps (100%) = tick # 1_000

        return tick * tickScaleFactor;
    }

    /// @notice Given some tick and a specified starting price, returns the price at that tick
    /// @param tick The tick to convert to a price
    /// @param tickScaleFactor The tickScaleFactor to use for the conversion
    /// @param startingPrice The price at which the tick starts
    function tickToPrice(uint24 tick, uint256 tickScaleFactor, uint256 startingPrice) public pure returns (uint256) {
        return (startingPrice * tickToBps(tick, tickScaleFactor)) / (10_000 / tickScaleFactor);
    }

    /// @notice Given some price and a specified starting price, returns the tick at that price
    /// @param price The price to convert to a tick
    /// @param tickScaleFactor The tickScaleFactor to use for the conversion
    /// @param startingPrice The price at which the tick starts
    function priceToTick(uint256 price, uint256 tickScaleFactor, uint256 startingPrice) public pure returns (uint24) {
        return bpsToTick((price * (10_000 / tickScaleFactor)) / startingPrice, tickScaleFactor);
    }
}
