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

    mapping(address => uint) public currentAssetPrices;
    mapping(address => mapping(uint => uint)) public historicalAssetPrices;

    constructor(address _univ3SwapRouter) CollarEngine(_univ3SwapRouter) { }

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

    function forceRegisterVaultManager(address user, address vaultManager) external {
        addressToVaultManager[user] = vaultManager;
        vaultManagers.add(vaultManager);
    }
}
