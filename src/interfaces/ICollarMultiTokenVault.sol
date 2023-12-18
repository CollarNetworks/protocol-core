// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ERC6909 } from "@solmate/tokens/ERC6909.sol";

abstract contract ICollarMultiTokenVault is ERC6909 {

    mapping(bytes32 uuid => uint256 totalCashSupply) tokenCashSupply;

    function redeem(bytes32 uuid, uint256 amount) external virtual;

    function previewRedeem(bytes32 uuid, uint256 amount) external virtual returns (uint256);
}