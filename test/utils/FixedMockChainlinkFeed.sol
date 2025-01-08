// SPDX-License-Identifier: GPL-2.0
pragma solidity 0.8.22;

import { IChainlinkFeedLike } from "../../src/interfaces/IChainlinkFeedLike.sol";

contract FixedMockChainlinkFeed is IChainlinkFeedLike {
    uint8 public immutable decimals;
    string public _description;
    int private immutable fixedPrice;

    constructor(int _fixedPrice, uint8 feedDecimals, string memory feedDescription) {
        decimals = feedDecimals;
        _description = feedDescription;
        fixedPrice = _fixedPrice;
    }

    /// @notice returns the description of the mockfeed for human readable config sanity checks.
    /// If _description is ABC, return FixedMock(ABC)
    function description() external view override(IChainlinkFeedLike) returns (string memory) {
        return string.concat("FixedMock(", _description, ")");
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int answer, uint startedAt, uint updatedAt, uint80 answeredInRound)
    {
        answer = fixedPrice;
        // Set other Chainlink feed fields
        roundId = uint80(block.number);
        startedAt = block.timestamp - 300;
        updatedAt = block.timestamp;
        answeredInRound = roundId;

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
