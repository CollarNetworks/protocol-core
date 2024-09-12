// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

/// common utils for simple math operations
abstract contract MathUtils {
    function _divUp(uint x, uint y) internal pure returns (uint) {
        return (x == 0) ? 0 : ((x - 1) / y) + 1; // divUp(x,y) = (x-1 / y) + 1
    }

    function _max(uint a, uint b) internal pure returns (uint) {
        return a > b ? a : b;
    }

    function _min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
}
