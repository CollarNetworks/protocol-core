// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { OracleLibrary } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import { IPeripheryImmutableState } from
    "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";

/// The warning below copied from Euler: https://github.com/euler-xyz/euler-price-oracle/blob/95e5d325cd9f4290d147821ff08add14ca99b136/src/adapter/uniswap/UniswapV3Oracle.sol#L14-L22
/// WARNING: READ THIS BEFORE DEPLOYING
/// Do not use Uniswap V3 as an oracle unless you understand its security implications.
/// Instead, consider using another provider as a primary price source.
/// Under PoS a validator may be chosen to propose consecutive blocks, allowing risk-free multi-block manipulation.
/// The cardinality of the observation buffer must be grown sufficiently to accommodate for the chosen TWAP window.
/// The observation buffer must contain enough observations to accommodate for the chosen TWAP window.
/// The chosen pool must have enough total liquidity and some full-range liquidity to resist manipulation.
/// The chosen pool must have had sufficient liquidity when past observations were recorded in the buffer.
/// Networks with short block times are highly susceptible to TWAP manipulation due to the reduced attack cost.
contract OracleUniV3 {
    uint32 internal constant MIN_TWAP_WINDOW = 5 minutes;

    uint128 public constant BASE_TOKEN_AMOUNT = 1e18;
    string public constant VERSION = "0.2.0";

    address public immutable baseToken;
    address public immutable quoteToken;
    uint24 public immutable feeTier;
    uint32 public immutable twapWindow;
    IUniswapV3Pool public immutable pool;

    /// Adapted from Euler: https://github.com/euler-xyz/euler-price-oracle/blob/95e5d325cd9f4290d147821ff08add14ca99b136/src/adapter/uniswap/UniswapV3Oracle.sol#L46-L56
    constructor(
        address _baseToken,
        address _quoteToken,
        uint24 _feeTier,
        uint32 _twapWindow,
        address _uniV3SwapRouter
    ) {
        if (_twapWindow < MIN_TWAP_WINDOW || _twapWindow > uint32(type(int32).max)) {
            revert("invalid TWAP window");
        }
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        feeTier = _feeTier;
        twapWindow = _twapWindow;
        // get and check the pool
        address uniV3Factory = IPeripheryImmutableState(_uniV3SwapRouter).factory();
        address poolAddress = IUniswapV3Factory(uniV3Factory).getPool(baseToken, quoteToken, feeTier);
        if (poolAddress == address(0)) revert("invalid oracle config");
        pool = IUniswapV3Pool(poolAddress);
    }

    // ----- Views ----- //

    function currentCardinality() public view returns (uint16 observationCardinalityNext) {
        (,,,,observationCardinalityNext,,) = pool.slot0();
    }

    function currentTWAP() external view returns (uint) {
        return historicalTWAP(uint32(block.timestamp));
    }

    function historicalTWAP(uint32 twapEndTime) public view returns (uint) {
        // _secondsAgos is in offsets format. e.g., [120, 60] means that observations 120 and 60
        // seconds ago will be used for the TWAP calculation
        uint32[] memory secondsAgos = new uint32[](2);
        uint32 twapEndOffset = uint32(block.timestamp) - twapEndTime;
        secondsAgos[0] = twapEndOffset + twapWindow;
        secondsAgos[1] = twapEndOffset;

        return _getQuote(secondsAgos);
    }

    // ----- Mutative ----- //

    function increaseCardinality(uint16 toAdd) external {
        pool.increaseObservationCardinalityNext(currentCardinality() + toAdd);
    }

    // ----- Internal Views ----- //

    /// Adapted from Euler: https://github.com/euler-xyz/euler-price-oracle/blob/95e5d325cd9f4290d147821ff08add14ca99b136/src/adapter/uniswap/UniswapV3Oracle.sol#L73-L78
    function _getQuote(uint32[] memory secondsAgos) internal view virtual returns (uint) {
        // Calculate the mean tick over the twap window.
        /// @dev this can revert with error OLD() if either value in secondsAgo is out of range of available observations
        (int56[] memory tickCumulatives,) = pool.observe(secondsAgos);
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 tick = int24(tickCumulativesDelta / int56(uint56(twapWindow)));
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(twapWindow)) != 0)) tick--;
        return OracleLibrary.getQuoteAtTick(tick, BASE_TOKEN_AMOUNT, baseToken, quoteToken);
    }
}
