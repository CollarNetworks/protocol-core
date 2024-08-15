// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { OracleUniV3TWAP } from "../../src/OracleUniV3TWAP.sol";

contract MockOracleUniV3TWAP is OracleUniV3TWAP {
    mapping(uint timestamp => uint value) historicalPrices;

    constructor(address _baseToken, address _quoteToken)
        OracleUniV3TWAP(_baseToken, _quoteToken, 0, MIN_TWAP_WINDOW, address(0))
    {
        // setup a non zero price for taker constructor sanity checks
        setHistoricalAssetPrice(block.timestamp, 1);
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
