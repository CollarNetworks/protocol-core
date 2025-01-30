// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { ERC721, Strings } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { BaseManaged, ConfigHub } from "./BaseManaged.sol";

/**
 * @title BaseNFT
 * @notice Base contract for NFTs in the Collar Protocol. It provides the admin functionality
 * from BaseManaged, and ensures token transfers are paused when the contract is paused.
 */
abstract contract BaseNFT is BaseManaged, ERC721 {
    string internal constant BASE_URI = "https://services.collarprotocol.xyz/metadata/";

    // ----- State ----- //
    uint internal nextTokenId = 1; // NFT token ID, starts from 1 so that 0 ID is not used

    constructor(
        address _initialOwner,
        string memory _name,
        string memory _symbol,
        ConfigHub _configHub,
        address _unrescuableAsset
    ) BaseManaged(_initialOwner, _configHub, _unrescuableAsset) ERC721(_name, _symbol) { }

    // ----- INTERNAL MUTATIVE ----- //

    // @dev this pauses transfers (as implemented in ERC721Pausable)
    function _update(address to, uint tokenId, address auth)
        internal
        override
        whenNotPaused
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    // @dev used by ERC721.tokenURI to create tokenID specific metadata URIs
    function _baseURI() internal view virtual override returns (string memory) {
        return string.concat(
            BASE_URI, Strings.toString(block.chainid), "/", Strings.toHexString(address(this)), "/"
        );
    }
}
