// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {BaseManaged, ConfigHub } from "./BaseManaged.sol";

abstract contract BaseNFT is BaseManaged, ERC721 {
    // ----- State ----- //
    uint internal nextTokenId = 1; // NFT token ID, starts from 1 so that 0 ID is not used

    constructor(address _initialOwner, string memory _name, string memory _symbol)
        BaseManaged(_initialOwner)
        ERC721(_name, _symbol)
    { }

    // ----- INTERNAL MUTATIVE ----- //

    // @dev from ERC721Pausable, to allow pausing transfers
    function _update(address to, uint tokenId, address auth)
        internal
        override
        whenNotPaused // @dev pauses transfers
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }
}
