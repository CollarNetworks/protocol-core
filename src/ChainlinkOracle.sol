// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Strings } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { BaseTakerOracle } from "./base/BaseTakerOracle.sol";
import { IChainlinkFeedLike } from "./interfaces/IChainlinkFeedLike.sol";

/**
 * @title ChainlinkOracle
 * @custom:security-contact security@collarprotocol.xyz
 * @notice Provides price from a Chainlink feed.
 * @dev Check feed address and params vs. https://docs.chain.link/data-feeds/price-feeds/addresses
 *
 * Key Assumptions:
 * - Chainlink price feed configuration matches expectation.
 * - The sequencer (on L2 networks) is operating properly, and its uptime feed (if used) is reliable.
 *
 * @dev references:
 * Euler: https://github.com/euler-xyz/euler-price-oracle/blob/0572b45f6096f42f290b7cf7df584226815bfa52/src/adapter/chainlink/ChainlinkOracle.sol
 */
contract ChainlinkOracle is BaseTakerOracle {
    string public constant VERSION = "0.2.0";

    // @notice time sequencer needs to have been up for, to expect that chainlink feeds
    // have been updated if needed (moved by more than deviation, or heartbeat time reached)
    // Chainlink use 1 hours in their example code:
    //  https://docs.chain.link/data-feeds/l2-sequencer-feeds#example-code
    // But this time is in mind with users to be able to update their positions (e.g., health)
    // and they don't mention how quickly their own feeds will start working.
    // We'll use 1 hour too to be conservative.
    uint public constant MIN_SEQUENCER_UPTIME = 1 hours;

    // The minimum permitted value for `maxStaleness`.
    uint internal constant MAX_STALENESS_MIN = 1 minutes;
    // The maximum permitted value for `maxStaleness`.
    uint internal constant MAX_STALENESS_MAX = 72 hours;

    /// @notice The Chainlink price feed.
    IChainlinkFeedLike public immutable priceFeed;
    /// @notice The maximum allowed age of the price (updatedAt) relative to block.timestamp
    /// @dev Consider setting `_maxStaleness` to slightly more than the feed's heartbeat
    /// to account for possible network delays when the heartbeat is triggered.
    uint public immutable maxStaleness;
    /// @notice unit amount of quote asset (10 ** quote-decimals)
    uint public immutable quoteUnitAmount;
    /// @notice unit amount of feed answer (10 ** feed-decimals). Assumed to not change for a feed.
    uint public immutable feedUnitAmount;

    constructor(
        address _baseToken,
        address _quoteToken,
        address _priceFeed,
        string memory _feedDescription,
        uint _maxStaleness,
        address _sequencerChainlinkFeed
    ) BaseTakerOracle(_baseToken, _quoteToken, _sequencerChainlinkFeed) {
        require(
            _maxStaleness >= MAX_STALENESS_MIN && _maxStaleness <= MAX_STALENESS_MAX,
            "ChainlinkOracle: staleness out of range"
        );
        maxStaleness = _maxStaleness;
        priceFeed = IChainlinkFeedLike(_priceFeed);
        require(
            Strings.equal(priceFeed.description(), _feedDescription), "ChainlinkOracle: description mismatch"
        );

        // set unit amounts for price conversion
        quoteUnitAmount = 10 ** IERC20Metadata(_quoteToken).decimals();
        feedUnitAmount = 10 ** priceFeed.decimals();
    }

    /// @notice Current price of a unit of base tokens (i.e. 10**baseToken.decimals()) in quote tokens.
    /// @dev checks sequencer uptime feed if it was set
    function currentPrice() public view override returns (uint) {
        // check sequencer feed
        if (address(sequencerChainlinkFeed) != address(0)) {
            require(sequencerLiveFor(MIN_SEQUENCER_UPTIME), "ChainlinkOracle: sequencer uptime interrupted");
        }
        // get the price oracle answer
        (, int answer,, uint updatedAt,) = priceFeed.latestRoundData();
        // check staleness
        require(block.timestamp - updatedAt <= maxStaleness, "ChainlinkOracle: stale price");
        // check answer in range
        require(answer > 0, "ChainlinkOracle: invalid price");
        // feed answer is already for unit (baseUnitAmount), but at feed precision (of feedUnitAmount).
        // to translate it to quote precision, we divide by feedUnitAmount and multiply by quoteUnitAmount
        return uint(answer) * quoteUnitAmount / feedUnitAmount;
    }
}
