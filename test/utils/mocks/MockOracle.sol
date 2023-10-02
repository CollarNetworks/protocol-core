// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Test} from "@forge-std/Test.sol";
import {AggregatorV3Interface} from "@chainlink-v0.8/interfaces/AggregatorV3Interface.sol";

contract MockOracle is Test, AggregatorV3Interface {
    // Values initialized to 1 to help debugging
    uint80 internal roundId = 1;
    int256 internal answer = 1;
    uint256 internal startedAt = 1;
    uint256 internal updatedAt = 1;
    uint80 internal answeredInRound = 1;

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
        returns (uint80 _roundId, int256 _answer, uint256 _startedAt, uint256 _updatedAt, uint80 _answeredInRound)
    {
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function setLatestRoundData(int256 _answer) external {
        answer = _answer;
    }
}
