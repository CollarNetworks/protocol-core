// SPDX-License-Identifier: GPL 2.0
pragma solidity 0.8.22;

/// Partial chainlink AggregatorV2V3Interface used in AAVE in for its sequencer uptime checks:
/// https://github.com/aave-dao/aave-v3-origin/blob/077c99e8002514f1f487e3707824c21ac19cf12e/src/contracts/interfaces/ISequencerOracle.sol
interface IChainlinkFeedLike {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound);
}
