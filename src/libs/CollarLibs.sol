// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { PoolAddress } from "@uniswap/v3-periphery/contracts/libraries/PoolAddress.sol";
import { OracleLibrary } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

/// @notice Various constants used throughout the system
abstract contract Constants {
    // one hundred percent, in basis points
    uint256 public constant ONE_HUNDRED_PERCENT = 10_000;

    // precision multiplier to be used when expanding small numbers before division, etc
    uint256 public constant PRECISION_MULTIPLIER = 1e18;
}

library CollarOracle {
    function getTWAP(
        address baseToken,
        address quoteToken,
        uint32 twapStartTimestamp,
        uint32 twapLength,
        address uniswapV3Factory
    )
        external
        view
        returns (uint256 price)
    {
        address poolToUse = _getPoolForTokenPair(baseToken, quoteToken, uniswapV3Factory);
        IUniswapV3Pool pool = IUniswapV3Pool(poolToUse);
        int24 tick;
        if (twapLength == 0) {
            // return the current price if twapInterval == 0
            (, tick,,,,,) = pool.slot0();
        } else {
            uint32[] memory _secondsAgos = new uint32[](2);
            // Calculate *how long ago* the timestamp passed in as a parameter is,
            // so that we can use this in the "offset" part
            // First, we calculate what the offset is to the *end* of the twap (aka offset to timeStampStart)
            // THEN, we factor in the twapLength to the timestamp that we actually want to start the twap from
            uint32 offset = (uint32(block.timestamp) - twapStartTimestamp) + twapLength;
            _secondsAgos[0] = twapLength + offset;
            _secondsAgos[1] = offset;
            (int56[] memory tickCumulatives,) = pool.observe(_secondsAgos);
            int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
            int56 period = int56(int32(twapLength));
            // Always round to negative infinity
            if (tickCumulativesDelta < 0 && (tickCumulativesDelta % period != 0)) tick--;
            tick = int24(tickCumulativesDelta / period);
        }

        price = OracleLibrary.getQuoteAtTick(tick, 1e18, baseToken, quoteToken);
    }

    // function getCurrentAssetPrice(address /*asset*/ ) external view virtual override returns (uint256) {
    //     revert("Method not yet implemented");
    // }

    /**
     * pulled from mean finance static oracle
     */

    /// @notice Takes a pair and some fee tiers, and returns pool
    function _getPoolForTokenPair(
        address _tokenA,
        address _tokenB,
        address uniswapV3Factory
    )
        internal
        pure
        returns (address _pool)
    {
        PoolAddress.PoolKey memory _poolKey = PoolAddress.getPoolKey(_tokenA, _tokenB, 3000);
        _pool = PoolAddress.computeAddress(address(uniswapV3Factory), _poolKey);
    }
}
