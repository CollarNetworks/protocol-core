// SPDX-License-Identifier: GPL 2.0
pragma solidity 0.8.22;

// The interface that is relied on by CollarTakerNFT (and the contracts using the oracle through / from it)
interface ITakerOracle {
    // constants
    function baseToken() external view returns (address);
    function quoteToken() external view returns (address);
    function baseUnitAmount() external view returns (uint128);
    // price views
    function currentPrice() external view returns (uint);
    function pastPriceWithFallback(uint32 timestamp) external view returns (uint price, bool historical);
    // logic helpers
    function convertToBaseAmount(uint quoteTokenAmount, uint atPrice) external view returns (uint);
    function convertToQuoteAmount(uint baseTokenAmount, uint atPrice) external view returns (uint);
}
