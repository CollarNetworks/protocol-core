// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity ^0.8.18;

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { ERC4626 } from "@openzeppelin/contracts/token/ERC4626/ERC4626.sol";

abstract contract CollarFungibleToken is ERC1155 {

    constructor(string memory _name) ERC1155(_name) { }

    function _mint(bytes32 uuid, uint256 amount) internal virtual;
    function _redeem(bytes32 uuid, uint256 amount) internal virtual;

    function _previewMint(bytes32 uuid, uint256 amount) internal virtual returns (bool);
    function _previewRedeem(bytes32 uuid, uint256 amount) internal virtual returns (bool);



}