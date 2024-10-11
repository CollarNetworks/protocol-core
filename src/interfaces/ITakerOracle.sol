// SPDX-License-Identifier: GPL 2.0
pragma solidity 0.8.22;

// The interface that is relied on by CollarTakerNFT (and the contracts using the oracle through / from it)
interface ITakerOracle {
    function baseToken() external view returns (address);
    function quoteToken() external view returns (address);
    function currentPrice() external view returns (uint);
    function pastPriceWithFallback(uint32 timestamp) external view returns (uint price, bool historical);
    function BASE_TOKEN_AMOUNT() external view returns (uint128);
}
