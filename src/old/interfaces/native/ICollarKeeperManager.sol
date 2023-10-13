// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface ICollarKeeperManager {
    function launchMaturityKeeper(address vault, uint256 maturityTimestamp) external;
}
