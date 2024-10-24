// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { OracleLibrary, IUniswapV3Pool } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import { IPeripheryImmutableState } from
    "@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol";

import { ITakerOracle } from "./interfaces/ITakerOracle.sol";
import { IChainlinkFeedLike } from "./interfaces/IChainlinkFeedLike.sol";

/*
WARNING: READ THIS BEFORE DEPLOYING regarding using Uniswap v3 TWAP as an oracle.

------
Some warnings copied from Euler:
https://github.com/euler-xyz/euler-price-oracle/blob/95e5d325cd9f4290d147821ff08add14ca99b136/src/adapter/uniswap/UniswapV3Oracle.sol#L14-L22
> Do not use Uniswap V3 as an oracle unless you understand its security implications.
> Instead, consider using another provider as a primary price source.
> Under PoS a validator may be chosen to propose consecutive blocks, allowing risk-free multi-block manipulation.
> The cardinality of the observation buffer must be grown sufficiently to accommodate for the chosen TWAP window.
> The observation buffer must contain enough observations to accommodate for the chosen TWAP window.
> The chosen pool must have enough total liquidity and some full-range liquidity to resist manipulation.
> The chosen pool must have had sufficient liquidity when past observations were recorded in the buffer.
------

These mitigations should be in place when using this oracle:
- First, read this https://medium.com/@chinmayf/so-you-want-to-use-twap-1f992f9d3819
- Cardinality should be increased to cover the needed time window. If cardinality < time window, in extreme
volatility, if every block has a pool action, time window will not be available. Contracts should be
designed such that this risk (short infrequent DoS) should be acceptable (with low likelihood), or
cardinality should be increased above twap window.
- Pool liquidity should be deep and wide. Ideally, at least some full range liquidity should be in place.
This means that stable pair pools are especially risky, since tend to have liquidity in a very narrow range.
Arbitrage is expected only within good liquidity range (outside of it is not worth to the arbitrageurs).
- Lack of arbitrage or insufficiently responsive arbitrage (slower than twap window), means pool can be
manipulated (while taking some risk). Example: https://x.com/mudit__gupta/status/1455627465678749696
- L2 sequencer MEV, outages, or partial outages (e.g., preventing most arbitrage txs), need to be taken into
account when setting the time window. A censoring sequencer, that can exclude arbitrage transactions for
the duration of the window can manipulate the price.
- Liquidity can migrate between pools and dexes, so contracts should allow switching oracles.
- Continuously monitor (see below) the pool (and its replacements) suitability and switch as needed.
- Recommend large protocol LPs to maintain some full-range liquidity in pools they have significant
exposure to.

Suggested monitoring for pools and possible replacement pools (other fee tiers):
- Liquidity amount.
- Full range liquidity amount.
- Liquidity depth (trade size required to move price by +-X%).
- Age of oldest available observation (to detect when cardinality is insufficient).
- Pool price delay during spikes behind external market price (Binance / Chainlink) prices
to measure arbitrage responsiveness.
*/

/**
 * @custom:security-contact security@collarprotocol.xyz
 */
contract OracleUniV3TWAP is ITakerOracle {
    uint32 public constant MIN_TWAP_WINDOW = 300;
    string public constant VERSION = "0.2.0";

    address public immutable baseToken;
    address public immutable quoteToken;
    uint public immutable baseUnitAmount;
    uint24 public immutable feeTier;
    uint32 public immutable twapWindow;
    IUniswapV3Pool public immutable pool;
    /// @dev can be zero-address, since only exists on arbi-mainnet, but not on arbi-sepolia
    IChainlinkFeedLike public immutable sequencerChainlinkFeed;

    constructor(
        address _baseToken,
        address _quoteToken,
        uint24 _feeTier,
        uint32 _twapWindow,
        address _uniV3SwapRouter,
        address _sequencerChainlinkFeed
    ) {
        require(_twapWindow >= MIN_TWAP_WINDOW, "twap window too short");
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        feeTier = _feeTier;
        twapWindow = _twapWindow;
        baseUnitAmount = 10 ** IERC20Metadata(_baseToken).decimals();
        // sanity check decimals for casting in _getQuote
        require(baseUnitAmount <= type(uint128).max, "invalid decimals");
        pool = IUniswapV3Pool(_getPoolAddress(_uniV3SwapRouter));
        sequencerChainlinkFeed = IChainlinkFeedLike(_sequencerChainlinkFeed);
    }

    // ----- Views ----- //

    /// @dev adapted from AAVE:
    /// @param `atLeast` time is needed to check that sequencer has been live long enough, to ensure some
    /// assumptions are valid, e.g., DEX arbitrage was possible for at least that time.
    /// https://github.com/aave-dao/aave-v3-origin/blob/077c99e8002514f1f487e3707824c21ac19cf12e/src/contracts/misc/PriceOracleSentinel.sol#L71-L74
    /// More on sequencer uptime chainlink feeds: https://docs.chain.link/data-feeds/l2-sequencer-feeds
    function sequencerLiveFor(uint atLeast) public view virtual returns (bool) {
        if (address(sequencerChainlinkFeed) == address(0)) {
            // only arbi-mainnet has this oracle, for arbi-sepolia, 0 address is expected
            return true;
        } else {
            (, int answer, uint startedAt,,) = sequencerChainlinkFeed.latestRoundData();
            /* Explanation for the logic below:
                1. answer: 0 means up, 1 down
                2. startedAt is the latest change of status because this oracle is updated via L1->L2,
                only on changes. This is different from usual feeds that are updated periodically.
                E.g., in Oct 2024, startedAt of Arbitrum mainnet feed (0xFdB631F5EE196F0ed6FAa767959853A9F217697D)
                was was 1713187535, or 15th Apr 2024 (190 days prior).
                These are the latest triggers of updateStatus in the feed's aggregator:
                    https://arbiscan.io/address/0xC1303BBBaf172C55848D3Cb91606d8E27FF38428

                Using a longer `atLeast` value will result in longer wait time for "settling down",
                and can result in DoS periods if feed starts to be updated frequently.
            */
            return answer == 0 && block.timestamp - startedAt >= atLeast;
        }
    }

    function currentPrice() public view returns (uint) {
        return pastPrice(uint32(block.timestamp));
    }

    function pastPrice(uint32 timestamp) public view returns (uint) {
        // _secondsAgos is in offsets format. e.g., [120, 60] means that observations 120 and 60
        // seconds ago will be used for the TWAP calculation
        uint32 secondsAgo = uint32(block.timestamp) - timestamp; // will revert for future timestamp
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo + twapWindow;
        secondsAgos[1] = secondsAgo;
        // check that that sequencer was live for the duration of the twapWindow
        // @dev for historical price, if sequencer was up then, but was interrupted
        // since, this will revert ("false positive"). Because TWAP prices are not long living,
        // this false positive is unlikely, and the fallback price should be used if available.
        require(sequencerLiveFor(secondsAgos[0]), "sequencer uptime interrupted");
        // get the price from the pool
        return _getQuote(secondsAgos);
    }

    /// Tries to use a past price, but if that fails (because TWAP values for timestamp aren't available)
    /// it uses the current price.
    /// Current simple fallback means that there is a sharp difference in settlement
    /// price once the historical price becomes unavailable (because the price jumps to latest).
    /// @dev Use the oracle's `increaseCardinality` (or the pool's `increaseObservationCardinalityNext` directly)
    /// to force the pool to store a longer history of prices to increase the time span during which settlement
    /// uses the actual expiry price instead of the latest price.
    /// A more sophisticated fallback is possible - that will try to use the oldest historical price available,
    /// but that requires a more complex and tight integration with the pool.
    function pastPriceWithFallback(uint32 timestamp) public view returns (uint price, bool historical) {
        // high level try/catch is error-prone and hides failure cases, low level try/catch is more
        // complex so also not ideal. If reviewing changes to this must read docs:
        //    https://docs.soliditylang.org/en/v0.8.22/control-structures.html#try-catch
        // The "try" can revert on decode error, but it's impossible since this is calling self.
        try this.pastPrice(timestamp) returns (uint _price) {
            return (_price, true);
        } catch {
            // fallback to current price in case it is available, do not check error reason
            return (currentPrice(), false);
        }
    }

    /// logic helper to encapsulate the conversion and baseUnitAmount usage. Rounds down.
    /// will panic for 0 price (invalid)
    function convertToBaseAmount(uint quoteTokenAmount, uint atPrice) external view returns (uint) {
        // oracle price is for baseTokenAmount tokens
        return quoteTokenAmount * baseUnitAmount / atPrice;
    }

    /// logic helper to encapsulate the conversion and baseUnitAmount usage. Rounds down.
    function convertToQuoteAmount(uint baseTokenAmount, uint atPrice) external view returns (uint) {
        // oracle price is for baseTokenAmount tokens
        return baseTokenAmount * atPrice / baseUnitAmount;
    }

    function currentCardinality() public view returns (uint16 observationCardinalityNext) {
        (,,,, observationCardinalityNext,,) = pool.slot0();
    }

    // ----- Mutative ----- //

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
