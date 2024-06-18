// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { OracleLibrary } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

library TestPriceOracle {
    uint24 internal constant FEE_TIER_30_BIPS = 3000;
    uint128 internal constant BASE_TOKEN_AMOUNT = 1e18;

    function getUnsafePrice(
        address baseToken,
        address quoteToken,
        address uniswapV3Factory
    )
        internal
        view
        returns (uint)
    {
        IUniswapV3Pool pool = IUniswapV3Pool(
            IUniswapV3Factory(uniswapV3Factory).getPool(baseToken, quoteToken, FEE_TIER_30_BIPS)
        );

        (, int24 tick,,,,,) = pool.slot0();

        return OracleLibrary.getQuoteAtTick(tick, BASE_TOKEN_AMOUNT, baseToken, quoteToken);
    }
}
