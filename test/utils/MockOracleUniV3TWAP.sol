// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import { OracleUniV3TWAP } from "./OracleUniV3TWAP.sol";

contract MockOracleUniV3TWAP is OracleUniV3TWAP {
    // 0 prices can happen, but also sometimes unset price needs to revert to tigger fallback logic
    bool public checkPrice = false;

    // always reverts price views
    bool public reverts = false;

    mapping(uint timestamp => uint value) historicalPrices;

    constructor(address _baseToken, address _quoteToken)
        OracleUniV3TWAP(_baseToken, _quoteToken, 0, MIN_TWAP_WINDOW, address(0), address(0))
    {
        // setup a non zero price for taker constructor sanity checks
        setHistoricalAssetPrice(block.timestamp, 1);
    }

    function setHistoricalAssetPrice(uint timestamp, uint value) public {
        historicalPrices[timestamp] = value;
    }

    function setCheckPrice(bool enabled) public {
        checkPrice = enabled;
    }

    function setReverts(bool _reverts) public {
        reverts = _reverts;
    }

    // ----- Internal Views ----- //

    function _getPoolAddress(address _uniV3SwapRouter) internal pure override returns (address) {
        _uniV3SwapRouter;
        return address(0);
    }

    function _getQuote(uint32[] memory secondsAgos) internal view override returns (uint price) {
        require(!reverts, "oracle reverts");
        price = historicalPrices[block.timestamp - secondsAgos[1]];
        if (checkPrice) require(price != 0, "MockOracleUniV3TWAP: price unset for time");
    }
}
