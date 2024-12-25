// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { OracleLibrary, IUniswapV3Pool } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import { IPeripheryImmutableState } from
    "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";

import { BaseTakerOracle } from "../../src/base/BaseTakerOracle.sol";

/*
WARNING: READ THIS BEFORE DEPLOYING regarding using Uniswap v3 TWAP as an oracle.

------
Some warnings copied from Euler:
https://github.com/euler-xyz/euler-price-oracle/blob/95e5d325cd9f4290d147821ff08add14ca99b136/src/adapter/uniswap/UniswapV3Oracle.sol#L14-L22
> Do not use Uniswap V3 as an oracle unless you understand its security implications.
> The cardinality of the observation buffer must be grown sufficiently to accommodate for the chosen TWAP window.
> The observation buffer must contain enough observations to accommodate for the chosen TWAP window.
> The chosen pool must have enough total liquidity and some full-range liquidity to resist manipulation.
> The chosen pool must have had sufficient liquidity when past observations were recorded in the buffer.
------

These mitigations should be in place when using this oracle:
- First, read this https://medium.com/@chinmayf/so-you-want-to-use-twap-1f992f9d3819
- Cardinality should be increased to cover the needed time window. If cardinality < time window, in extreme
volatility, if every block (with new timestamp) has a pool action, time window will not be available. Contracts
should be designed such that this risk (short infrequent DoS) should be acceptable (with low likelihood), or
cardinality should be increased above twap window.
- Pool liquidity should be deep and wide. Ideally, at least some full range liquidity should be in place.
This means that stable pair pools are especially risky, since tend to have liquidity in a very narrow range.
Arbitrage is expected only within deep liquidity range (outside of it is not worth to the arbitrageurs).
- Lack of arbitrage or insufficiently responsive arbitrage (slower than twap window), means pool can be
manipulated (while taking some risk). Example: https://x.com/mudit__gupta/status/1455627465678749696
- L2 sequencer MEV, outages, congestion, partial outages (e.g., preventing most arbitrage txs), need to be
taken into account when setting the time window. A censoring sequencer, that can exclude arbitrage transactions
for the duration of the window can manipulate the price.
- Liquidity can migrate between pools and dexes, so contracts should allow switching oracles.
- Continuously monitor (see below) the pool (and its replacements) suitability and switch as needed.
- Recommend large protocol LPs to maintain some full-range liquidity in pools they have significant
exposure to.

Suggested monitoring for pools and possible replacement pools (other fee tiers):
- Liquidity amount.
- Full range liquidity amount.
- Liquidity depth (trade size required to move price by +-X%).
- Age of oldest available observation (to detect when cardinality may become insufficient).
- Price delay / delta during price spikes, as measured relative to external market price (Binance / Chainlink)
to measure arbitrage responsiveness.
*/

/**
 * @title OracleUniV3TWAP
 * @custom:security-contact security@collarprotocol.xyz
 * @notice Provides time-weighted average price (TWAP) oracle functionality using Uniswap v3 pools.
 *
 * @dev Read the WARNING at the top.
 *
 * Key Assumptions:
 * - The Uniswap v3 pool used has adequate liquidity to provide meaningful TWAP data.
 * - The pool's observation cardinality is adequate.
 * - The sequencer (on L2 networks) is operating properly, and its uptime feed (if used) is reliable.
 *
 * Post-Deployment Configuration:
 * - Uniswap pool: increase cardinality to adequate level
 */
contract OracleUniV3TWAP is BaseTakerOracle {
    uint32 public constant MIN_TWAP_WINDOW = 300;

    string public constant VERSION = "0.2.0";

    uint24 public immutable feeTier;
    uint32 public immutable twapWindow;
    IUniswapV3Pool public immutable pool;

    constructor(
        address _baseToken,
        address _quoteToken,
        uint24 _feeTier,
        uint32 _twapWindow,
        address _uniV3SwapRouter,
        address _sequencerChainlinkFeed
    ) BaseTakerOracle(_baseToken, _quoteToken, _sequencerChainlinkFeed) {
        // sanity check base decimals for casting in _getQuote
        require(baseUnitAmount <= type(uint128).max, "invalid base decimals");
        // check twap window not too short
        require(_twapWindow >= MIN_TWAP_WINDOW, "twap window too short");
        feeTier = _feeTier;
        twapWindow = _twapWindow;
        pool = IUniswapV3Pool(_getPoolAddress(_uniV3SwapRouter));
    }

    /// @notice Current TWAP price. Will revert if sequencer uptime check
    /// fails (if sequencer uptime feed is set), or if the TWAP window is not available for
    /// the twapWindow.
    /// @return Amount of quoteToken for a "unit" of baseToken (i.e. 10**baseToken.decimals())
    function currentPrice() public view override returns (uint) {
        uint32[] memory secondsAgos = new uint32[](2);
        // _secondsAgos is in offsets format. e.g., [120, 60] means that observations 120 and 60
        // seconds ago will be used for the TWAP calculation
        (secondsAgos[0], secondsAgos[1]) = (twapWindow, 0);
        // 0 address is expected for arbi-sepolia since only arbi-mainnet has the sequencer uptime oracle.
        if (address(sequencerChainlinkFeed) != address(0)) {
            // check that that sequencer was live for the duration of the twapWindow
            require(sequencerLiveFor(twapWindow), "sequencer uptime interrupted");
        }
        // get the price from the pool
        return _getQuote(secondsAgos);
    }

    function inversePrice() external pure override returns (uint) {
        revert("not implemented");
    }

    /// @notice Returns the current observation cardinality of the pool
    function currentCardinality() public view returns (uint16 observationCardinalityNext) {
        (,,,, observationCardinalityNext,,) = pool.slot0();
    }

    /// @notice returns the description of the oracle for human readable config sanity checks.
    function description() external view virtual returns (string memory) {
        revert("not implemented");
    }

    // ----- Mutative ----- //

    /// @notice Increases the observation cardinality of the pool
    /// @param toAdd The number of observations to extend the currently configured cardinality by
    function increaseCardinality(uint16 toAdd) external {
        pool.increaseObservationCardinalityNext(currentCardinality() + toAdd);
    }

    // ----- Internal Views ----- //

    /// Adapted from Euler:
    ///     https://github.com/euler-xyz/euler-price-oracle/blob/95e5d325cd9f4290d147821ff08add14ca99b136/src/adapter/uniswap/UniswapV3Oracle.sol#L46-L56
    function _getPoolAddress(address _uniV3SwapRouter) internal view virtual returns (address poolAddress) {
        address uniV3Factory = IPeripheryImmutableState(_uniV3SwapRouter).factory();
        poolAddress = IUniswapV3Factory(uniV3Factory).getPool(baseToken, quoteToken, feeTier);
    }

    /// Adapted from Euler:
    ///     https://github.com/euler-xyz/euler-price-oracle/blob/95e5d325cd9f4290d147821ff08add14ca99b136/src/adapter/uniswap/UniswapV3Oracle.sol#L73-L78
    function _getQuote(uint32[] memory secondsAgos) internal view virtual returns (uint) {
        // Calculate the mean tick over the twap window.
        /// @dev will revert with error OLD() if any value in secondsAgo is not in available observations
        (int56[] memory tickCumulatives,) = pool.observe(secondsAgos);
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 tick = int24(tickCumulativesDelta / int56(uint56(twapWindow)));
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int56(uint56(twapWindow)) != 0)) tick--;
        return OracleLibrary.getQuoteAtTick(tick, uint128(baseUnitAmount), baseToken, quoteToken);
    }
}
