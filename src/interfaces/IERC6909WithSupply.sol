// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ERC6909 } from "@solmate/tokens/ERC6909.sol";

abstract contract IERC6909WithSupply is ERC6909 {
    mapping(uint256 id => uint256) public totalTokenSupply;
}