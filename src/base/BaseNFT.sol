// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import { ERC721, Strings } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import { BaseManaged, ConfigHub } from "./BaseManaged.sol";

/**
 * @title BaseNFT
 * @notice Base contract for NFTs in the protocol. It provides the admin functionality
 * from BaseManaged, and the NFT metadata base URI.
 */
abstract contract BaseNFT is BaseManaged, ERC721 {
    string internal constant BASE_URI = "https://services.collarprotocol.xyz/metadata/";

    // ----- State ----- //
    uint internal nextTokenId = 1; // NFT token ID, starts from 1 so that 0 ID is not used

    constructor(string memory _name, string memory _symbol, ConfigHub _configHub)
        BaseManaged(_configHub)
        ERC721(_name, _symbol)
    { }

    // ----- INTERNAL ----- //

    // @dev used by ERC721.tokenURI to create tokenID specific metadata URIs
    function _baseURI() internal view virtual override returns (string memory) {
        return string.concat(
            BASE_URI, Strings.toString(block.chainid), "/", Strings.toHexString(address(this)), "/"
        );
    }
}
