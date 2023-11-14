// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import "../interfaces/IProportionalDividendsPool.sol";

contract ProportionalDividendsPool is IProportionalDividendsPool {
    function payDividends(uint24 tick, uint256 amount) public virtual override {
        
    }
}