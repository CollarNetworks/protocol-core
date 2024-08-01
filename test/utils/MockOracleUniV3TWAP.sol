// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { OracleUniV3TWAP } from "../../src/OracleUniV3TWAP.sol";

contract MockOracleUniV3TWAP is OracleUniV3TWAP {
    mapping(uint timestamp => uint value) historicalPrices;

    constructor(
        address _baseToken,
        address _quoteToken,
        uint24 _feeTier,
        uint32 _twapWindow,
        address _uniV3SwapRouter,
        uint currentPrice
    ) OracleUniV3TWAP(_baseToken, _quoteToken, _feeTier, _twapWindow, _uniV3SwapRouter) {
        setHistoricalAssetPrice(block.timestamp, currentPrice);
    }

    function setHistoricalAssetPrice(uint timestamp, uint value) public {
        historicalPrices[timestamp] = value;
    }

    // ----- Internal Views ----- //

    function _getPoolAddress(address _uniV3SwapRouter) internal pure override returns (address) {
        _uniV3SwapRouter;
        return address(0);
    }

    function _getQuote(uint32[] memory secondsAgos) internal view override returns (uint) {
        return historicalPrices[block.timestamp - secondsAgos[1]];
    }
}
