// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

// The interface that is relied on by contracts
interface ITakerOracle {
    function baseToken() external view returns (address);
    function quoteToken() external view returns (address);
    function currentPrice() external view returns (uint);
    function pastPriceWithFallback(uint32 timestamp) external view returns (uint price, bool historical);
    function BASE_TOKEN_AMOUNT() external view returns (uint128);
}
