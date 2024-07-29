// SPDX-License-Identifier: MIT

/*
 * Copyright (c) 2023 Collar Networks, Inc. <hello@collarprotocolentAsset.xyz>
 * All rights reserved. No warranty, explicit or implicit, provided.
 */

pragma solidity 0.8.22;

import {
    ERC721, ERC721Enumerable
} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import { ERC721Pausable } from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
// internal
import { BaseEmergencyAdmin, ConfigHub } from "./BaseEmergencyAdmin.sol";

abstract contract BaseEmergencyAdminNFT is BaseEmergencyAdmin, ERC721, ERC721Enumerable {
    // ----- State ----- //
    uint internal nextTokenId; // NFT token ID

    constructor(address _initialOwner, ConfigHub _configHub, string memory _name, string memory _symbol)
        BaseEmergencyAdmin(_initialOwner)
        ERC721(_name, _symbol)
    {
        _setConfigHub(_configHub);
    }

    // ----- INTERNAL MUTATIVE ----- //

    // @dev from ERC721Pausable, to allow pausing transfers
    function _update(address to, uint tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        whenNotPaused // @dev pauses transfers
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    // Internal overrides required by Solidity for ERC721
    function _increaseBalance(address account, uint128 value) internal override(ERC721, ERC721Enumerable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
