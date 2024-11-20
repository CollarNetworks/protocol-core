// SPDX-License-Identifier: GPL 2.0
pragma solidity 0.8.22;

/// Partial chainlink AggregatorV2V3Interface used in Euler:
/// https://github.com/euler-xyz/euler-price-oracle/blob/0572b45f6096f42f290b7cf7df584226815bfa52/src/adapter/chainlink/AggregatorV3Interface.sol
interface IChainlinkFeedLike {
    /// @notice Returns the feed's decimals.
    /// @return The decimals of the feed.
    function decimals() external view returns (uint8);

    /// @notice returns the description of the aggregator the proxy points to.
    function description() external view returns (string memory);

    /// @notice Get data about the latest round.
    /// @return roundId The round ID from the aggregator for which the data was retrieved.
    /// @return answer The answer for the given round.
    /// @return startedAt The timestamp when the round was started.
    /// (Only some AggregatorV3Interface implementations return meaningful values)
    /// @return updatedAt The timestamp when the round last was updated (i.e. answer was last computed).
    /// @return answeredInRound is the round ID of the round in which the answer was computed.
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound);
}
