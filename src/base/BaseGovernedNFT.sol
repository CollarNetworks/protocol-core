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

abstract contract BaseGovernedNFT is Ownable, ERC721, ERC721Enumerable, ERC721Pausable {
    // ----- State ----- //
    uint internal nextTokenId; // NFT token ID

    constructor(
        address initialOwner,
        string memory _name,
        string memory _symbol
    )
        ERC721(_name, _symbol)
        Ownable(initialOwner)
    { }

    // ----- INTERNAL MUTATIVE ----- //

    // Emergency actions

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // Internal overrides required by Solidity for ERC721

    function _update(
        address to,
        uint tokenId,
        address auth
    )
        internal
        override(ERC721, ERC721Enumerable, ERC721Pausable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

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
