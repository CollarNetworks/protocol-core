// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { OracleLibrary } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

library UniV3OracleLib {
    uint24 internal constant FEE_TIER_30_BIPS = 3000;
    uint128 internal constant BASE_TOKEN_AMOUNT = 1e18;

    /// @dev refernce implementation:
    ///     https://github.com/euler-xyz/euler-price-oracle/blob/master/src/adapter/uniswap/UniswapV3Oracle.sol
    function getTWAP(
        address baseToken,
        address quoteToken,
        uint32 twapEndTimestamp,
        uint32 twapLength,
        address uniswapV3Factory
    ) internal view returns (uint) {
        // _secondsAgos is in offsets format. e.g., [120, 60] means that observations 120 and 60
        // seconds ago will be used for the TWAP calculation
        uint32[] memory secondsAgos = new uint32[](2);
        uint32 twapEndOffset = uint32(block.timestamp) - twapEndTimestamp;
        secondsAgos[0] = twapEndOffset + twapLength;
        secondsAgos[1] = twapEndOffset;

        int56[] memory tickCumulatives =
            _getObservations(baseToken, quoteToken, uniswapV3Factory, secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int56 period = int56(uint56(twapLength));
        int24 tick = int24(tickCumulativesDelta / period);
        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % period != 0)) tick--;

        return OracleLibrary.getQuoteAtTick(tick, BASE_TOKEN_AMOUNT, baseToken, quoteToken);
    }

    function _getObservations(
        address baseToken,
        address quoteToken,
        address uniswapV3Factory,
        uint32[] memory secondsAgos
    ) internal view returns (int56[] memory) {
        address pool = IUniswapV3Factory(uniswapV3Factory).getPool(baseToken, quoteToken, FEE_TIER_30_BIPS);
        (int56[] memory tickCumulatives,) = IUniswapV3Pool(pool).observe(secondsAgos);
        return tickCumulatives;
    }
}
