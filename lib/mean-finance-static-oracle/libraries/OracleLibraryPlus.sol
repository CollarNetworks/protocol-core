// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.18;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "forge-std/console.sol";

library OracleLibraryPlus {
    /// @notice Calculates time-weighted means of tick and liquidity for a given Uniswap V3 pool
    /// @param _pool Address of the pool that we want to observe
    /// @param _twapLength Length in seconds of the TWAP calculation length
    /// @param _offset Number of seconds ago to start the TWAP calculation
    /// @return _arithmeticMeanTick The arithmetic mean tick from _secondsAgos[0] to _secondsAgos[1]
    /// @return _harmonicMeanLiquidity The harmonic mean liquidity from _secondsAgos[0] to _secondsAgos[1]
    function consultOffsetted(address _pool, uint32 _twapLength, uint32 _offset)
        internal
        view
        returns (int24 _arithmeticMeanTick, uint128 _harmonicMeanLiquidity)
    {
        uint32[] memory _secondsAgos = new uint32[](2);
        _secondsAgos[0] = _twapLength + _offset;
        _secondsAgos[1] = _offset;

        (int56[] memory _tickCumulatives, uint160[] memory secondsPerLiquidityCumulativeX128s) = IUniswapV3Pool(_pool).observe(_secondsAgos);

        int56 _tickCumulativesDelta = _tickCumulatives[1] - _tickCumulatives[0];
        uint160 _secondsPerLiquidityCumulativesDelta = secondsPerLiquidityCumulativeX128s[1] - secondsPerLiquidityCumulativeX128s[0];
        console.log("tickCumulativesDelta");
        console.logInt(_tickCumulativesDelta);
        _arithmeticMeanTick = int24(_tickCumulativesDelta / int56(int32(_twapLength)));
        // Always round to negative infinity
        if ((_tickCumulativesDelta < 0) && (_tickCumulativesDelta % int56(int32(_twapLength)) != 0)) _arithmeticMeanTick--;
        console.log("arithmeticMeanTick: ");
        console.logInt(_arithmeticMeanTick);

        // We are multiplying here instead of shifting to ensure that _harmonicMeanLiquidity doesn't overflow uint128
        uint192 _secondsAgoX160 = uint192(_twapLength) * type(uint160).max;
        _harmonicMeanLiquidity = uint128(_secondsAgoX160 / (uint192(_secondsPerLiquidityCumulativesDelta) << 32));
    }
}
