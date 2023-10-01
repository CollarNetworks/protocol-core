// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Test} from "@forge-std/Test.sol";
import {AggregatorV3Interface} from "@chainlink-v0.8/interfaces/AggregatorV3Interface.sol";

contract MockOracle is Test, AggregatorV3Interface {
    int256 internal latestAnswer = 1;

    function decimals() external pure returns (uint8) {
        revert("Not yet implemented.");
    }

    function description() external pure returns (string memory) {
        revert("Not yet implemented.");
    }

    function version() external pure returns (uint256) {
        revert("Not yet implemented.");
    }

    function getRoundData(uint80 /*_roundId*/ ) external pure returns (uint80, int256, uint256, uint256, uint80) {
        revert("Not yet implemented.");
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, latestAnswer, 0, 0, 0);
    }

    function setLatestRoundData(int256 answer) external {
        latestAnswer = answer;
    }
}
