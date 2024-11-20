// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { ITakerOracle } from "../interfaces/ITakerOracle.sol";
import { IChainlinkFeedLike } from "../interfaces/IChainlinkFeedLike.sol";

abstract contract BaseTakerOracle is ITakerOracle {
    address public immutable baseToken;
    address public immutable quoteToken;
    uint public immutable baseUnitAmount;
    /// @dev can be zero-address if unset. Can be unset if it's unreliable, or because doesn't exist
    /// on a network (like arbi-sepolia)
    IChainlinkFeedLike public immutable sequencerChainlinkFeed;

    constructor(address _baseToken, address _quoteToken, address _sequencerChainlinkFeed) {
        baseToken = _baseToken;
        quoteToken = _quoteToken;
        baseUnitAmount = 10 ** IERC20Metadata(_baseToken).decimals();
        sequencerChainlinkFeed = IChainlinkFeedLike(_sequencerChainlinkFeed);
    }

    // ----- Views ----- //

    /// @return Amount of quoteToken for a "unit" of baseToken (i.e. 10**baseToken.decimals())
    function currentPrice() external view virtual returns (uint);

    /**
     * @notice Checks whether the sequencer uptime Chainlink feed reports the sequencer to be live
     * for at least the specified amount of time. Reverts if feed was not set (is address zero).
     * @dev adapted from AAVE:
     * `atLeast` time is needed to check that sequencer has been live long enough, to ensure some
     * assumptions are valid, e.g., DEX arbitrage was possible for at least that time.
     *  https://github.com/aave-dao/aave-v3-origin/blob/077c99e8002514f1f487e3707824c21ac19cf12e/src/contracts/misc/PriceOracleSentinel.sol#L71-L74
     * More on sequencer uptime chainlink feeds: https://docs.chain.link/data-feeds/l2-sequencer-feeds
     * @param atLeast The duration of time for which the sequencer should have been live for until now.
     * @return true if sequencer is live now and was live for atLeast seconds up until now
     */
    function sequencerLiveFor(uint atLeast) public view virtual returns (bool) {
        require(address(sequencerChainlinkFeed) != address(0), "sequencer uptime feed unset");

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

    /**
     * @notice Calculates the amount of quote tokens equivalent to the amount of base tokens at a given price
     * @dev Logic helper to encapsulate the conversion and baseUnitAmount usage. Rounds down.
     * Will panic for 0 price (invalid)
     * @param quoteTokenAmount The amount of quote tokens
     * @param atPrice The price to use for the conversion
     * @return The equivalent amount of base tokens
     */
    function convertToBaseAmount(uint quoteTokenAmount, uint atPrice) external view returns (uint) {
        // oracle price is for baseTokenAmount tokens
        return quoteTokenAmount * baseUnitAmount / atPrice;
    }

    /**
     * @notice Calculates the amount of base tokens equivalent to the amount of quote tokens at a given price
     * @dev Logic helper to encapsulate the conversion and baseUnitAmount usage. Rounds down.
     * @param baseTokenAmount The amount of base tokens
     * @param atPrice The price to use for the conversion
     * @return The equivalent amount of quote tokens
     */
    function convertToQuoteAmount(uint baseTokenAmount, uint atPrice) external view returns (uint) {
        // oracle price is for baseTokenAmount tokens
        return baseTokenAmount * atPrice / baseUnitAmount;
    }
}
