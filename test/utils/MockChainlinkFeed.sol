// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

contract MockChainlinkFeed {
    string public description;
    uint8 public decimals;

    bool public reverts = false;

    int public answer;
    uint public updatedAt;

    constructor(uint8 _decimals, string memory _description) {
        decimals = _decimals;
        description = _description;
    }

    function latestRoundData() external view returns (uint80, int, uint, uint, uint80) {
        require(!reverts, "oracle reverts");
        return (0, answer, 0, updatedAt, 0);
    }

    function setReverts(bool _reverts) public {
        reverts = _reverts;
    }

    function setLatestAnswer(int _answer, uint _updatedAt) public {
        answer = _answer;
        updatedAt = _updatedAt;
    }
}
