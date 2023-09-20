// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ICollarEngine {
    function getOraclePrice() external view returns (uint256);
    // function setKeeperManager(address) external;
}
