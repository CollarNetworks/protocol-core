// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { CollarEngine } from "../../src/implementations/CollarEngine.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract MockEngine is CollarEngine {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    mapping(address => uint256) public currentAssetPrices;
    mapping(address => mapping(uint256 => uint256)) public historicalAssetPrices;

    constructor(address _dexRouter) CollarEngine(_dexRouter) { }

    function setHistoricalAssetPrice(address asset, uint256 timestamp, uint256 value) external {
        historicalAssetPrices[asset][timestamp] = value;
    }

    function getHistoricalAssetPrice(address asset, uint256 timestamp) external view virtual override returns (uint256) {
        return historicalAssetPrices[asset][timestamp];
    }

    function setCurrentAssetPrice(address asset, uint256 price) external {
        currentAssetPrices[asset] = price;
    }

    function getCurrentAssetPrice(address asset) external view virtual override returns (uint256) {
        return currentAssetPrices[asset];
    }

    function forceRegisterVaultManager(address user, address vaultManager) external {
        addressToVaultManager[user] = vaultManager;
        vaultManagers.add(vaultManager);
    }
}
