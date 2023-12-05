// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ICollarEngine } from "../../src/protocol/interfaces/IEngine.sol";
import { CollarEngine } from "../../src/protocol/implementations/Engine.sol";

contract MockEngine is CollarEngine {
    mapping(address asset => mapping(uint256 timestamp => uint256 price)) public historicalAssetPrices;
    mapping(address asset => uint256) public currentAssetPrices;

    constructor(address _core, address _collarLiquidityPoolManager, address _dexRouter) CollarEngine(_core, _collarLiquidityPoolManager, _dexRouter) {}

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
}

