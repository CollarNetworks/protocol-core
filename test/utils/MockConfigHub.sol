// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { ConfigHub } from "../../src/implementations/ConfigHub.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract MockConfigHub is ConfigHub {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    mapping(address => uint) public currentAssetPrices;
    mapping(address => mapping(uint => uint)) public historicalAssetPrices;

    constructor(address _initialOwner, address _univ3SwapRouter) ConfigHub(_initialOwner, _univ3SwapRouter) { }

    function setHistoricalAssetPrice(address asset, uint timestamp, uint value) external {
        historicalAssetPrices[asset][timestamp] = value;
    }

    function getHistoricalAssetPrice(address asset, uint timestamp) external view virtual returns (uint) {
        return historicalAssetPrices[asset][timestamp];
    }

    function setCurrentAssetPrice(address asset, uint price) external {
        currentAssetPrices[asset] = price;
    }

    function getHistoricalAssetPriceViaTWAP(
        address baseToken,
        address quoteToken,
        uint32 timeStampStart,
        uint32 twapLength
    ) external view virtual override returns (uint) {
        return historicalAssetPrices[baseToken][timeStampStart];
    }
}
